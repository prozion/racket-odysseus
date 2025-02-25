#lang racket

(require "optimize.rkt")
(require racket/serialize)
(require compatibility/defmacro)
(require (for-syntax racket/match racket/syntax racket/format))

(provide (all-defined-out))

(define (varname-is-hash? varname)
  (regexp-match #rx"^h-|^H" (format "~a" varname)))

(define-macro (persistent varname)
  (let ((varname-str (format "~a" varname)))
    `(define ,varname
                        (λ args
                          (let* (
                                (varname-is-hash? (varname-is-hash? ',varname))
                                ; (_ (--- (printf (format "~a ~a" ',varname varname-is-hash?))))
                                (cache-path (cond
                                              ((absolute-path? CACHE_DIR) (format "~a/~a.rktd" CACHE_DIR (string-replace ,varname-str "-" "_")))
                                              (else (format "../~a/~a.rktd" CACHE_DIR (string-replace ,varname-str "-" "_")))))
                                (cache-exists? (file-exists? cache-path))
                                (value-to-add (match args
                                                  ((list (list x) _ ...) (list x))
                                                  ((list x _ ...) x)
                                                  (_ #f)))
                                (option1 (match args
                                            ((list _ x _ ...) x)
                                            (_ #f)))
                                (option2 (match args
                                            ((list _ _ x _ ...) x)
                                            (_ #f)))
                                (append? (and option1 (equal? option1 'append)))
                                (duplicate-saved-file? (and option2 (equal? option2 'dup)))
                                (overwrite? (not append?))
                                (value-changed? #t)
                                (old-value (and cache-exists? (read-serialized-data-from-file cache-path)))
                                (new-value
                                    (cond
                                      ((and value-to-add append? varname-is-hash?)
                                          (hash-union value-to-add (or old-value (hash))))
                                      ((and value-to-add append?)
                                          remove-duplicates
                                            (append
                                              (or old-value empty)
                                              (if (list? value-to-add)
                                                  value-to-add
                                                  (list value-to-add))))
                                      ((and value-to-add varname-is-hash?)
                                          value-to-add)
                                      ((and value-to-add (list? value-to-add))
                                          value-to-add)
                                      ((and value-to-add)
                                          (list value-to-add))
                                      ((and cache-exists?)
                                          (set! value-changed? #f)
                                          old-value)
                                      ((and varname-is-hash?)
                                          (hash))
                                      (else empty))))
                            (when duplicate-saved-file? (write-data-to-file new-value (format "~a_" cache-path)))
                            (when value-changed? (write-data-to-file new-value cache-path))
                            new-value)))))

(define-macro (read-or-evaluate persistent-name expr)
  `(if (nil? (,persistent-name))
      (let ((res ,expr))
        (,persistent-name res)
        res)
      (,persistent-name)))

(define-macro (purge-persistent persistent-name)
  `(cond
    ((varname-is-hash? ,persistent-name) (hash))
    (else empty)))
