(use-modules (srfi srfi-64)
             (srfi srfi-1)
             (concurrency channel))


(test-begin "Simple Tests")

(test-assert (channel? (make-channel)))

(test-end "Simple Tests")

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
                                       (channel-get c))))))
    (join-thread s0)
    (join-thread r0)
    (and (thread-exited? s0) (thread-exited? r0))
    received))

(test-begin "One to One")

(test-assert (sender-then-receiver))
(test-assert (receiver-then-sender))
(test-assert (receiver-gets-value 42))
(test-assert (receiver-gets-value "foo"))
(test-assert (receiver-gets-value (list 1 2 3)))
(test-assert (receiver-gets-value-t-times 30 42))
(test-assert (receiver-gets-value-t-times 42 "foo"))

(test-end "One to One")

(define (sender-then-receivers number-of-receivers v)
  (let* ((c (make-channel))
         (s0 (call-with-new-thread (lambda () (channel-put c v))))
         (receivers
          (do ((i 0 (1+ i))
               (rs (list (call-with-new-thread (lambda () (channel-get c))))
                   (cons (call-with-new-thread (lambda () (channel-get c))) rs)))
              ((<= number-of-receivers i) rs))))
    (join-thread s0)
    (= (count thread-exited? receivers) 1)))

(define (receivers-then-sender number-of-receivers v)
  (let* ((c (make-channel))
         (receivers
          (do ((i 0 (1+ i))
               (rs (list (call-with-new-thread (lambda () (channel-get c))))
                   (cons (call-with-new-thread (lambda () (channel-get c))) rs)))
              ((<= number-of-receivers i) rs)))
         (s0 (call-with-new-thread (lambda () (channel-put c v)))))
    (join-thread s0)
    (= (count thread-exited? receivers) 1)))

(test-begin "One Sender, Multiple Receivers")

(test-assert (sender-then-receivers 42 42))
(test-assert (sender-then-receivers 42 "foo"))
(test-assert (receivers-then-sender 42 42))
(test-assert (receivers-then-sender 42 "foo"))

(test-end "One Sender, Multiple Receivers")
