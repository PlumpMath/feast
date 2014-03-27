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
  #:export (make-channel channel? channel-put channel-get))

;;; Values used to know if there is something on the channel
(define no-value '(no-value))
(define receiver-waiting '(receiver-waiting))

(define-record-type <channel>
  (%make-channel receiver-mutex sender-mutex mutex cv v)
  channel?
  (receiver-mutex receiver-mutex)
  (sender-mutex sender-mutex)
  (mutex mutex)
  (cv cv)
  (v channel-value set-channel-value!))

(set-record-type-printer! <channel>
                          (lambda (record port)
                            (display "#<channel>" port)))

(define (make-channel)
  "Return a channel."
  (%make-channel (make-mutex) (make-mutex) (make-mutex)
                 (make-condition-variable) no-value))

(define (channel-get ch)
  "Get a value from the channel CH.

If there is no value availabe, it will block the caller until there is
one."
  (with-mutex (receiver-mutex ch)
    (take-value ch)))

(define (channel-put ch v)
  "Put a value into the channel CH.

If there is no one waiting for a value, it will block until a getter
appears."
  (with-mutex (sender-mutex ch)
    (put-value ch v)))

(define (sender-waiting? ch)
  (not (eq? (channel-value ch) no-value)))

(define (receiver-waiting? ch)
  (eq? (channel-value ch) receiver-waiting))

(define (take-value ch)
  "Take a value from the channel.

It blocks the thread if there is no thread waiting with a value."
  ;; There should be only one thread getting a value from the channel
  (with-mutex (mutex ch)
    (when (not (sender-waiting? ch))
      ;; Blocks until there is a sender in the channel
      (set-channel-value! ch receiver-waiting)
      (wait-condition-variable (cv ch) (mutex ch)))
    (let ((r (channel-value ch)))
      (set-channel-value! ch no-value)
      (signal-condition-variable (cv ch)) ;release the sender
      r)))

(define (put-value ch v)
  "Put a value into the channel.

It blocks the thread if there is no thread waiting for a value."
  ;; There should be only one thread putting a value into the channel
  (lock-mutex (mutex ch))
  (cond ((receiver-waiting? ch)
         (set-channel-value! ch v)
         (signal-condition-variable (cv ch))
         ;; wait for receiver to release us
         (unlock-mutex (mutex ch) (cv ch)))
        (else
         (set-channel-value! ch v)
         ;; wait for a receiver
         (wait-condition-variable (cv ch) (mutex ch))
         (unlock-mutex (mutex ch)))))
