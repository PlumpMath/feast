(define-module (concurrency channel)
  #:use-module (srfi srfi-9 gnu)
  #:use-module (ice-9 threads)
  #:export (list make-channel channel-put channel-get))

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
  (let ((reader-waiting-mutex (make-mutex 'allow-external-unlock))
        (sender-waiting-mutex (make-mutex 'allow-external-unlock)))
    (lock-mutex reader-waiting-mutex #f #f)
    (lock-mutex sender-waiting-mutex #f #f)
    (%make-channel (make-mutex) (make-mutex) (make-mutex)
                   sender-waiting-mutex (make-condition-variable)
                   reader-waiting-mutex (make-condition-variable))))

(define (channel-get ch)
  (with-mutex (channel-receiver-mutex ch)
              (take-value ch)))

(define (channel-put ch v)
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
