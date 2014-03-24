;;; channel.scm --- Data structure for threads synchronization

;; Copyright (C) 2014 Diogo F. S. Ramos <dfsr@riseup.net>

;; This program is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see
;; <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Channel is a data structure for synchronization between threads.

;; A thread can put or get values from a channel.  If there isn't
;; another thread at the other end, the thread will block until other
;; thread appears.

;; Multiple threads can put and get values from a single channel but
;; only two at a time can communicate.

;;; Code:

(define-module (concurrency channel)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-9 gnu)
  #:use-module (ice-9 threads)
  #:export (make-channel channel-put channel-get))

(define-record-type <channel>
  (%make-channel receiver-mutex sender-mutex shared-mutex
                 sender-waiting-mutex sender-condvar
                 reader-waiting-mutex reader-condvar)
  channel?
  (receiver-mutex channel-receiver-mutex)
  (sender-mutex channel-sender-mutex)
  (shared-mutex channel-shared-mutex)
  (sender-waiting-mutex channel-sender-waiting-mutex)
  (sender-condvar channel-sender-condvar)
  (reader-waiting-mutex channel-reader-waiting-mutex)
  (reader-condvar channel-reader-condvar)
  (v channel-value set-channel-value!))

(set-record-type-printer! <channel>
                          (lambda (record port)
                            (display "#<channel>" port)))

(define (make-channel)
  "Return a channel."
  (let ((reader-waiting-mutex (make-mutex 'allow-external-unlock))
        (sender-waiting-mutex (make-mutex 'allow-external-unlock)))
    (lock-mutex reader-waiting-mutex #f #f)
    (lock-mutex sender-waiting-mutex #f #f)
    (%make-channel (make-mutex) (make-mutex) (make-mutex)
                   sender-waiting-mutex (make-condition-variable)
                   reader-waiting-mutex (make-condition-variable))))

(define (channel-get ch)
  "Get a value from the channel CH.

If there is no value availabe, it will block the caller until there is
one."
  (with-mutex (channel-receiver-mutex ch)
              (take-value ch)))

(define (channel-put ch v)
  "Put a value into the channel CH.

If there is no one waiting for a value, it will block until a getter
appears."
  (with-mutex (channel-sender-mutex ch)
              (put-value ch v)))

(define (sender-waiting? ch)
  (not (mutex-locked? (channel-sender-waiting-mutex ch))))

(define (reader-waiting? ch)
  (not (mutex-locked? (channel-reader-waiting-mutex ch))))

(define (unlock-sender ch)
  (signal-condition-variable (channel-sender-condvar ch)))

(define (unlock-reader ch)
  (signal-condition-variable (channel-reader-condvar ch)))

(define (lock-sender ch)
  (wait-condition-variable (channel-sender-condvar ch)
                           (channel-sender-waiting-mutex ch)))

(define (lock-reader ch)
  (wait-condition-variable (channel-reader-condvar ch)
                           (channel-reader-waiting-mutex ch)))

(define (take-value ch)
  (let* ((value-read? #f)
         (v (with-mutex (channel-shared-mutex ch)
                        (when (sender-waiting? ch)
                          (unlock-sender ch)
                          (set! value-read? #t)
                          (channel-value ch)))))
    (cond (value-read? v)
          (else (lock-reader ch)
                (channel-value ch)))))

(define (put-value ch v)
  (let* ((value-put? #f))
    (with-mutex (channel-shared-mutex ch)
                (when (reader-waiting? ch)
                  (set-channel-value! ch v)
                  (unlock-reader ch)
                  (set! value-put? #t)))
    (cond (value-put? v)
          (else (set-channel-value! ch v)
                (lock-sender ch)))))
