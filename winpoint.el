;;; winpoint.el --- Remember buffer positions per-window, not per buffer

;; Copyright (C) 2006, 2012  Jorgen Schaefer

;; Version: 1.4
;; Author: Jorgen Schaefer <forcer@forcix.cx>
;; URL: https://github.com/jorgenschaefer/winpoint
;; Keywords: convenience

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
;; 02110-1301  USA

;;; Commentary:

;; When two windows view the same buffer at the same time, and one
;; window is switched to another buffer and back, point is now the
;; same as in the other window, not as it was before we switched away.
;; This mode tries to work around this problem by storing and
;; restoring per-window positions for each buffer.

;; To enable this, just run (winpoint-mode 1)

;;; Code:

(defvar winpoint-frame-windows nil
  "The current frame's windows and their buffers.
This is an alist mapping windows to their current buffers.")
(make-variable-frame-local 'winpoint-frame-windows)

(defvar winpoint-frame-positions nil
  "The current frame's windows and their associated buffer positions.
This is an alist mapping windows to an alist mapping buffers to
their stored point marker.")
(make-variable-frame-local 'winpoint-frame-positions)

;;;###autoload
(defalias 'window-point-remember-mode 'winpoint-mode)
;;;###autoload
(define-minor-mode winpoint-mode
  "Remember positions in a buffer per-window, not per-buffer.
That is, when you have the same buffer open in two different
windows, and you switch the buffer in one window and back again,
the position is the same as it was when you switched away, not
the same as in the other window."
  :global t
  (cond
   (winpoint-mode
    (add-hook 'post-command-hook 'winpoint-remember)
    (add-hook 'window-configuration-change-hook
              'winpoint-remember-configuration))
   (t
    (remove-hook 'post-command-hook 'winpoint-remember)
    (remove-hook 'window-configuration-change-hook
                 'winpoint-remember-configuration))))

(defun winpoint-remember ()
  "Remember the currently visible buffer's positions.
This should be put on `post-command-hook'."
  ;; (winpoint-put (selected-window)
  ;;             (current-buffer)
  ;;             (point)))
  (walk-windows (lambda (win)
                  (let ((buf (window-buffer win)))
                    (winpoint-put win
                                  buf
                                  (window-point win))))))

(defun winpoint-remember-configuration ()
  "This remembers the currently shown windows.
If any buffer wasn't shown before, point in that window is
restored.
If any window isn't shown anymore, forget about it."
  (winpoint-clean)
  (setq winpoint-frame-windows
        (mapcar (lambda (win)
                  (let ((old (assq win winpoint-frame-windows))
                        (newbuf (window-buffer win)))
                    (when (and old
                               (not (eq (cdr old)
                                        newbuf)))
                      (winpoint-restore win))
                    (cons win newbuf)))
                (window-list))))

;;; Emacs 21 compatibility
(eval-when-compile
  (when (not (fboundp 'with-selected-window))
    (defmacro with-selected-window (window &rest body)
      "Execute the forms in BODY with WINDOW as the selected window."
      `(save-selected-window
         (select-window ,window)
         ,@body))))

(defun winpoint-restore (win)
  "Restore point in the window WIN."
  (with-selected-window win
    (let ((point (winpoint-get win (current-buffer))))
      (when (and point
                 (not eq major-mode `dired-mode))
        (goto-char point)))))

;;;;;;;;;;;;;;;;
;;; Database API
(defun winpoint-get (win buf)
  "Return a cons cell of the stored point of BUF in WIN."
  (let ((window-entry (assq win winpoint-frame-positions)))
    (when window-entry
      (let ((buffer (assq buf (cdr window-entry))))
        (when buffer
          (cdr buffer))))))

(defun winpoint-put (win buf point)
  "Store POINT as the current point for BUF in WIN."
  (let ((window-entry (assq win winpoint-frame-positions)))
    (if window-entry
        (let ((buffer (assq buf (cdr window-entry))))
          (if buffer
              (set-marker (cdr buffer) point buf)
            (setcdr window-entry
                    (cons `(,buf . ,(set-marker (make-marker)
                                                point
                                                buf))
                          (cdr window-entry)))))
      (setq winpoint-frame-positions
            (cons `(,win . ((,buf . ,(set-marker (make-marker)
                                                 point
                                                 buf))))
                  winpoint-frame-positions)))))

(defun winpoint-clean ()
  "Remove unknown windows."
  (let ((windows (window-list)))
    (setq winpoint-frame-positions
          (filter-map! (lambda (entry)
                         (let ((bufs (filter! (lambda (buf+pos)
                                                (buffer-live-p (car buf+pos)))
                                              (cdr entry))))
                           (when (not (null bufs))
                             (cons (car entry)
                                   bufs))))
                       winpoint-frame-positions))))

(defun filter-map! (fun list)
  "Map FUN over LIST, retaining all non-nil elements."
  (while (and list
              (not (setcar list (funcall fun (car list)))))
    (setq list (cdr list)))
  (when list
    (let ((list list))
      (while (cdr list)
        (if (not (setcar (cdr list)
                         (funcall fun (cadr list))))
            (setcdr list (cddr list))
          (setq list (cdr list))))))
  list)

(defun filter! (pred list)
  "Return all elements of LIST for which PRED returns non-nil.
This modifies LIST whenever possible."
  (while (and list
              (not (funcall pred (car list))))
    (setq list (cdr list)))
  (when list
    (let ((list list))
      (while (cdr list)
        (if (not (funcall pred (cadr list)))
            (setcdr list (cddr list))
          (setq list (cdr list))))))
  list)

(provide 'winpoint)
;;; winpoint.el ends here
