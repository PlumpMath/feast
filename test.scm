#!/usr/bin/guile \
-e main -l channel.scm -s
!#

(use-modules (concurrency channel)
             (ice-9 format)
             (srfi srfi-1))

;;; Testing framework taken from the book Practical Common Lisp by
;;; Peter Seibel and translated to Guile.
(define test-name (make-parameter '()))

(define-syntax-rule (define-test (name args ...) exp exp* ...)
  (define (name args ...)
    (parameterize ((test-name (append (test-name)
                                      (list (syntax->datum #'name)))))
      exp exp* ...)))

(define-syntax-rule (combine-results exp ...)
  (let ((result #t))
    (unless exp (set! result #f)) ...
    result))

(define-syntax-rule (report-result result exp)
  (begin
    (format #t "~[FAIL~;pass~] ... ~a: ~s~%" (if result 1 0) (test-name) 'exp)
    result))

(define-syntax-rule (check exp ...)
  (combine-results (report-result 'exp exp) ...))
;;; end of the testing framework

(define-test (simple-tests)
  (check (channel? (make-channel))))

(define (sender-then-receiver)
  (let* ((c (make-channel))
         (s0 (call-with-new-thread (lambda () (channel-put c 42))))
         (r0 (call-with-new-thread (lambda () (channel-get c)))))
    (join-thread s0)
    (join-thread r0)
    (and (thread-exited? s0) (thread-exited? r0))))

(define (receiver-then-sender)
  (let* ((c (make-channel))
         (r0 (call-with-new-thread (lambda () (channel-get c))))
         (s0 (call-with-new-thread (lambda () (channel-put c 42)))))
    (join-thread s0)
    (join-thread r0)
    (and (thread-exited? s0) (thread-exited? r0))))

(define (receiver-gets-value v)
  (let* ((c (make-channel))
         (received #f)
         (s0 (call-with-new-thread (lambda () (channel-put c v))))
         (r0 (call-with-new-thread (lambda () (set! received (channel-get c))))))
    (join-thread s0)
    (join-thread r0)
    (and (thread-exited? s0) (thread-exited? r0))
    (equal? v received)))

(define (receiver-gets-value-t-times t v)
  (let* ((c (make-channel))
         (received #t)
         (s0 (call-with-new-thread (lambda ()
                                     (do ((i 0 (1+ i)))
                                         ((<= t i))
                                       (channel-put c v)))))
         (r0 (call-with-new-thread (lambda ()
                                     (do ((i 0 (1+ i)))
                                         ((<= t i))
                                       (when received
                                         (set! received
                                               (equal? v (channel-get c)))))))))
    (join-thread s0)
    (join-thread r0)
    (and (thread-exited? s0) (thread-exited? r0))
    received))

(define-test (one-to-one)
  (check (sender-then-receiver)
         (receiver-then-sender)
         (receiver-gets-value 42)
         (receiver-gets-value "foo")
         (receiver-gets-value (list 1 2 3))
         (receiver-gets-value-t-times 42 42)
         (receiver-gets-value-t-times 42 "foo")))

(define (sender-then-receivers number-of-receivers v)
  (let* ((c (make-channel))
         (s0 (call-with-new-thread (lambda () (channel-put c v))))
         (receivers
          (do ((i 0 (1+ i))
               (rs (call-with-new-thread (lambda () (channel-get c)))
                   (cons (call-with-new-thread (lambda () (channel-get c))) rs)))
              ((<= number-of-receivers i) rs))))
    (join-thread s0)
    (= (count thread-exited? receivers) 1)))

(define (receivers-then-senders number-of-receivers v)
  (let* ((c (make-channel))
         (receivers
          (do ((i 0 (1+ i))
               (rs (call-with-new-thread (lambda () (channel-get c)))
                   (cons (call-with-new-thread (lambda () (channel-get c))) rs)))
              ((<= number-of-receivers i) rs)))
         (s0 (call-with-new-thread (lambda () (channel-put c v)))))
    (join-thread s0)
    (= (count thread-exited? receivers) 1)))

(define-test (one-sender-multiple-receivers)
  (check (sender-then-receivers 42 42)
         (sender-then-receivers 42 "foo")
         (receivers-then-sender 42 42)
         (receivers-then-sender 42 "foo")))

(define-test (test-channel)
  (combine-results
   (simple-tests)
   (one-to-one)
   (one-sender-multiple-receivers)))

(define (main args)
  (test-channel))
