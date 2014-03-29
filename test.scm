(use-modules (ice-9 threads)
             (srfi srfi-64)
             (srfi srfi-1)
             (concurrency channel))


;;; utils
(define* (build-list n proc)
  (define (build-looping i)
    (if (<= n i)
        '()
        (cons (proc i) (build-looping (+ i 1)))))
  (build-looping 0))


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
  (let ((mx (make-mutex))
        (cv (make-condition-variable)))
    (with-mutex mx
      (let* ((c (make-channel))
             (s0 (call-with-new-thread (lambda () (channel-put c v))))
             (rv #f)
             (receivers
              (build-list number-of-receivers
                          (lambda (_)
                            (call-with-new-thread
                             (lambda ()
                               (let ((r (channel-get c)))
                                 (with-mutex mx
                                   (set! rv r)
                                   (signal-condition-variable cv)))))))))
        (join-thread s0)
        (wait-condition-variable cv mx)
        (for-each cancel-thread receivers)
        (equal? rv v)))))

(define (receivers-then-sender number-of-receivers v)
  (let ((mx (make-mutex))
        (cv (make-condition-variable)))
    (with-mutex mx
      (let* ((c (make-channel))
             (rv #f)
             (receivers
              (build-list number-of-receivers
                          (lambda (_)
                            (call-with-new-thread
                             (lambda ()
                               (let ((r (channel-get c)))
                                 (with-mutex mx
                                   (set! rv r)
                                   (signal-condition-variable cv))))))))
             (s0 (call-with-new-thread (lambda () (channel-put c v)))))
        (join-thread s0)
        (wait-condition-variable cv mx)
        (for-each cancel-thread receivers)
        (equal? rv v)))))

(test-begin "One Sender, Multiple Receivers")

(test-assert (sender-then-receivers 42 42))
(test-assert (sender-then-receivers 42 "foo"))
(test-assert (receivers-then-sender 42 42))
(test-assert (receivers-then-sender 42 "foo"))

(test-end "One Sender, Multiple Receivers")

(define (senders-then-receiver number-of-senders v)
  (let ((mx (make-mutex))
        (cv (make-condition-variable)))
    (with-mutex mx
      (let* ((c (make-channel))
             (senders (build-list number-of-senders
                                  (lambda (i)
                                    (call-with-new-thread
                                     (lambda ()
                                       (channel-put c v)
                                       (with-mutex mx
                                         (signal-condition-variable cv)))))))
             (rv #f)
             (r0 (call-with-new-thread (lambda ()
                                         (set! rv (channel-get c))))))
        (join-thread r0)
        (wait-condition-variable cv mx)
        (for-each cancel-thread senders)
        (equal? rv v)))))

(define (receiver-then-senders number-of-senders v)
  (let ((mx (make-mutex))
        (cv (make-condition-variable)))
    (with-mutex mx
      (let* ((c (make-channel))
             (rv #f)
             (r0 (call-with-new-thread (lambda ()
                                         (set! rv (channel-get c)))))
             (senders (build-list number-of-senders
                                  (lambda (i)
                                    (call-with-new-thread
                                     (lambda ()
                                       (channel-put c v)
                                       (with-mutex mx
                                         (signal-condition-variable cv))))))))
        (join-thread r0)
        (wait-condition-variable cv mx)
        (for-each cancel-thread senders)
        (equal? rv v)))))

(test-begin "Multiple Senders, Single receiver")

(test-assert (senders-then-receiver 42 42))
(test-assert (senders-then-receiver 42 "foo"))
(test-assert (receiver-then-senders 42 42))
(test-assert (receiver-then-senders 42 "foo"))

(test-end "Multiple Senders, Single receiver")

(define (senders-then-receivers number-of-threads v)
  (let* ((c (make-channel))
         (senders (build-list number-of-threads
                              (lambda (i)
                                (call-with-new-thread
                                 (lambda ()
                                   (channel-put c v))))))
         (receivers (build-list number-of-threads
                                (lambda (i)
                                  (call-with-new-thread
                                   (lambda ()
                                     (channel-get c)))))))
    (for-each join-thread senders)
    (for-each join-thread receivers)
    #t))

(define (receivers-then-senders number-of-threads v)
  (let* ((c (make-channel))
         (receivers (build-list number-of-threads
                                (lambda (i)
                                  (call-with-new-thread
                                   (lambda ()
                                     (channel-get c))))))
         (senders (build-list number-of-threads
                              (lambda (i)
                                (call-with-new-thread
                                 (lambda ()
                                   (channel-put c v)))))))
    (for-each join-thread senders)
    (for-each join-thread receivers)
    #t))

(define (senders-and-receivers number-of-threads v)
  (let* ((c (make-channel))
         (senders-and-receivers
          (build-list
           number-of-threads
           (lambda (i)
             (let* ((sender (call-with-new-thread
                             (lambda ()
                               (channel-put c v))))
                    (receiver (call-with-new-thread
                               (lambda ()
                                 (channel-get c)))))
               (cons sender receiver))))))
    (for-each (lambda (x)
                (join-thread (car x))
                (join-thread (cdr x)))
              senders-and-receivers)
    #t))

(define (receivers-and-senders number-of-threads v)
  (let* ((c (make-channel))
         (receivers-and-senders
          (build-list
           number-of-threads
           (lambda (i)
             (let* ((receiver (call-with-new-thread
                               (lambda ()
                                 (channel-get c))))
                    (sender (call-with-new-thread
                             (lambda ()
                               (channel-put c v)))))
               (cons receiver sender))))))
    (for-each (lambda (x)
                (join-thread (car x))
                (join-thread (cdr x)))
              receivers-and-senders)
    #t))

(test-begin "Multiple Senders, Multiple receivers")

(test-assert (senders-then-receivers 42 42))
(test-assert (receivers-then-senders 42 42))
(test-assert (senders-and-receivers 42 42))
(test-assert (receivers-and-senders 42 42))

(test-end "Multiple Senders, Multiple receivers")
