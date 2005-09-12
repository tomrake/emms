;;; emms-lyrics.el --- Display lyrics synchronically

;; Copyright (C) 2005 William XWL

;; Author: William XWL <william.xwl@gmail.com>
;; Keywords: emms music lyric

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
;; 02110-1301 USA

;;; Commentary:

;; This package enables you to play music files and display lyrics
;; synchronically! :-) It requires `emms-player-extensions'.

;; Put this file into your load-path and the following into your
;; ~/.emacs:
;;             (require 'emms-lyrics)

;; Take a look at the "User Customizable" part for possible personal
;; customizations.

;;; Change Log:

;; v 0.3 [2005/07/19 17:53:25] Add `emms-lyric-find-lyric' for find
;;       lyric files in local repository `emms-lyric-dir'. Rewrite
;;       `emms-lyric-setup' to support more lyric formats.

;; v 0.2 [2005/07/18 16:10:02] Fix `emms-lyric-pause' bug. Now it works
;;       fine. Add `emms-lyric-seek', but which does not work very well
;;       currently.

;; v 0.1 [2005/07/17 20:07:30] Initial version.

;;; Known bugs:

;; 1. Sometimes music playing would be blocked by some process, like
;;    startup Gnus, while emms-lyrics still goes on, thus make music and
;;    lyrics asynchronical.

;;; Todo:

;; 1. Maybe the lyric setup should run before `emms-start'.
;; 2. Give a user a chance to choose when finding out multiple lyrics.
;; 3. Search lyrics from internet ?

;;; Code:

(defvar emms-lyrics-version "0.4 $Revision: 1.14 $"
  "EMMS lyric version string.")
;; $Id: emms-lyric.el,v 1.14 2005/08/25 13:03:02 xwl Exp $

(require 'emms)
(require 'emms-player-simple)
(require 'emms-source-file)
(require 'emms-player-extensions)

;;; User Customizations
(defvar emms-lyrics-display-p t
  "Whether to diplay lyrics or not.")

(defvar emms-lyrics-display-on-modeline t
  "Display lyrics on mode line.")

(defvar emms-lyrics-display-on-minibuffer nil
  "Display lyrics on minibuffer.")

(defvar emms-lyrics-dir ""
  "The directory of local lyric files. `emms-lyrics-find-lyric' will look
for lyrics in current directory and here.")

(defvar emms-lyrics-display-format " %s "
  "Format for displaying lyric on mode-line.")

;;; Variables
(defvar emms-lyrics-alist nil
  "a list of the form: '((time0 lyric0) (time1 lyric1)...)). In short,
at time-i, display lyric-i.")

(defvar emms-lyrics-timers nil
  "timers for displaying lyric.")

(defvar emms-lyrics-start-time nil
  "emms lyric start time.")

(defvar emms-lyrics-pause-time nil
  "emms lyric pause time.")

(defvar emms-lyrics-elapsed-time 0
  "How long time has emms lyric played.")

(defvar emms-lyrics-mode-line-string ""
  "current lyric.")

;;; emms lyric control

(defun emms-lyrics-read-file (file)
  "Read a lyric file(LRC format). File should end up with \".lrc\", its
contents look like:

    [1:39]I love you, Emacs!
    [00:39]I love you, Emacs!
    [00:39.67]I love you, Emacs!

To find FILE, first look up in current directory, if not found, continue
looking up in `emms-lyrics-dir'."
  (when emms-lyrics-display-p
    (unless (file-exists-p file)
      (setq file (emms-lyrics-find-lyric file)))
    (when (and file (not (string= file "")) (file-exists-p file))
      (with-temp-buffer
	(insert-file-contents file)
	(while (search-forward-regexp "\\[[0-9:.]+\\].*" nil t)
	  (let ((lyric-string (match-string 0))
		(time 0)
		(lyric ""))
	    (setq lyric
		  (replace-regexp-in-string ".*\\]" "" lyric-string))
	    (while (string-match "\\[[0-9:.]+\\]" lyric-string)
	      (let* ((time-string (match-string 0 lyric-string))
		     (semi-pos (string-match ":" time-string)))
		(setq time
		      (+ (* (string-to-number
			     (substring time-string 1 semi-pos))
			    60)
			 (string-to-number
			  (substring time-string
				     (1+ semi-pos)
				     (1- (length time-string))))))
		(setq lyric-string
		      (substring lyric-string (length time-string)))
		(setq emms-lyrics-alist
		      (append emms-lyrics-alist `((,time ,lyric))))
		(setq time 0)))))
	t))))

(defun emms-lyrics-start ()
  "Start displaying lryics."
  (setq emms-lyrics-start-time (current-time)
	emms-lyrics-pause-time nil
	emms-lyrics-elapsed-time 0)
  (when (and emms-lyrics-display-p
	     (let ((file (cdaddr (emms-playlist-selected-track))))
	       (emms-lyrics-read-file
		(replace-regexp-in-string
		 (file-name-extension file) "lrc" file))))
    (emms-lyrics-set-timer)))

(add-hook 'emms-player-started-hook 'emms-lyrics-start)

(defun emms-lyrics-stop ()
  "Stop displaying lyrics."
  (interactive)
  (when (and emms-lyrics-display-p
	     emms-lyrics-alist)
    (cancel-function-timers 'emms-lyrics-display)
    (if (or (not emms-player-paused-p)
	    emms-player-stopped-p)
	(setq emms-lyrics-alist nil
	      emms-lyrics-timers nil
	      emms-lyrics-mode-line-string ""))))

(add-hook 'emms-player-stopped-hook 'emms-lyrics-stop)
(add-hook 'emms-player-finished-hook 'emms-lyrics-stop)

(defun emms-lyrics-pause ()
  "Pause displaying lyrics."
  (if emms-player-paused-p
      (setq emms-lyrics-pause-time (current-time))
    (when emms-lyrics-pause-time
      (setq emms-lyrics-elapsed-time
	    (+ (time-to-seconds
		(time-subtract emms-lyrics-pause-time
			       emms-lyrics-start-time))
	       emms-lyrics-elapsed-time)))
    (setq emms-lyrics-start-time (current-time)))
  (when (and emms-lyrics-display-p
	     emms-lyrics-alist)
    (if emms-player-paused-p
	(emms-lyrics-stop)
      (emms-lyrics-set-timer))))

(add-hook 'emms-player-paused-hook 'emms-lyrics-pause)

(defun emms-lyrics-seek (sec)
  "Seek forward or backward SEC seconds lyrics."
  (setq emms-lyrics-elapsed-time
	(+ emms-lyrics-elapsed-time
	   (time-to-seconds
	    (time-subtract (current-time)
			   emms-lyrics-start-time))
	   sec))
  (when (< emms-lyrics-elapsed-time 0)	; back to start point
    (setq emms-lyrics-elapsed-time 0))
  (setq emms-lyrics-start-time (current-time))
  (when (and emms-lyrics-display-p
	     emms-lyrics-alist)
    (let ((paused-orig emms-player-paused-p))
      (setq emms-player-paused-p t)
      (emms-lyrics-stop)
      (setq emms-player-paused-p paused-orig))
    (emms-lyrics-set-timer)))

(add-hook 'emms-player-seeked-hook 'emms-lyrics-seek)

(defun emms-lyrics-toggle-display-on-minibuffer ()
  "Toggle display lyric on minibbufer."
  (interactive)
  (if emms-lyrics-display-on-minibuffer
      (progn
	(setq emms-lyrics-display-on-minibuffer nil)
	(message "Disable lyric on minibufer."))
    (setq emms-lyrics-display-on-minibuffer t)
    (message "Enable lyric on minibufer.")))

(defun emms-lyrics-toggle-display-on-modeline ()
  "Toggle display lyric on modeline."
  (interactive)
  (if emms-lyrics-display-on-modeline
      (progn
	(setq emms-lyrics-display-on-modeline nil
	      emms-lyrics-mode-line-string "")
	(message "Disable lyric on modeline."))
    (setq emms-lyrics-display-on-modeline t)
    (message "Enable lyric on modeline.")))

(defun emms-lyrics-set-timer ()
  "Set timers for displaying lyrics."
  (setq emms-lyrics-timers
	(mapcar
	 '(lambda (arg)
	    (let ((time (- (car arg) emms-lyrics-elapsed-time))
		  (lyric (cadr arg)))
	      (when (>= time 0)
		(run-at-time (format "%d sec" time)
			     nil
			     'emms-lyrics-display
			     lyric))))
	 emms-lyrics-alist)))

(defun emms-lyrics-mode-line ()
  "Add lyric to the mode line."
  (unless (member 'emms-lyrics-mode-line-string
		  global-mode-string)
    (setq global-mode-string
	  (append global-mode-string
		  '(emms-lyrics-mode-line-string)))))

(defun emms-lyrics-display (lyric)
  "Display lyric.

LYRIC is current playing lyric.

See `emms-lyrics-display-on-modeline' and
`emms-lyrics-display-on-minibuffer' on how to config where to
display."
  (when (and emms-lyrics-display-p
	     emms-lyrics-alist)
    (when emms-lyrics-display-on-modeline
      (emms-lyrics-mode-line)
      (setq emms-lyrics-mode-line-string 
	    (format emms-lyrics-display-format lyric))
      (force-mode-line-update))
    (when emms-lyrics-display-on-minibuffer
      (message lyric))))

(defun emms-lyrics-find-lyric (file)
  "Use `emms-source-file-gnu-find' to find lrc FILE. You should specify
a valid `emms-lyrics-dir'."
  (unless (string= emms-lyrics-dir "")
    ;; If find two or more lyric files, only return the first one. Good
    ;; luck! :-)
    (car (split-string
	  (shell-command-to-string
	   (concat emms-source-file-gnu-find " "
		   emms-lyrics-dir " -name "
		   "'"			; wrap up whitespaces
		   (replace-regexp-in-string
		    "'" "*"		; FIX ME, '->\'
		    (file-name-nondirectory file))
		   "'"))
	  "\n"))))

;;; emms-lyrics-mode

(defun emms-lyrics-insert-time ()
  "Insert lyric time in the form: [01:23.21], then goto the
beginning of next line."
  (interactive)
  (let* ((total (+ (time-to-seconds
		    (time-subtract (current-time)
				   emms-lyrics-start-time))
		   emms-lyrics-elapsed-time))
	 (min (/ (* (floor (/ total 60)) 100) 100))
	 (sec (/ (floor (* (rem* total 60) 100)) 100.0)))
    (insert (replace-regexp-in-string
	     " " "0" (format "[%2d:%2d]" min sec))))
  (emms-lyrics-next-line))

(defun emms-lyrics-next-line ()
  "Goto the beginning of next line."
  (interactive)
  (forward-line 1))

(defun emms-lyrics-previous-line ()
  "Goto the beginning of previous line."
  (interactive)
  (forward-line -1))

(defvar emms-lyrics-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "p" 'emms-lyrics-previous-line)
    (define-key map "n" 'emms-lyrics-next-line)
    (define-key map "i" 'emms-lyrics-insert-time)
    map)
  "Keymap for `emms-lyrics-mode'.")

(defvar emms-lyrics-mode-hook nil
  "Normal hook run when entering Emms Lyric mode.")

(define-derived-mode emms-lyrics-mode nil "Emms Lyric"
  "Major mode for creating lyric files.
\\{emms-lyrics-mode-map}"
  (run-hooks 'emms-lyrics-mode-hook))


(provide 'emms-lyrics)

;;; emms-lyrics.el ends here