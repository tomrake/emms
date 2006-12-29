;;; emms-lastfm.el --- add your listened songs to your profile at last.fm

;; Copyright (C) 2006 Free Software Foundation, Inc.

;; Author: Tassilo Horn <tassilo@member.fsf.org>

;; Keywords: emms, mp3, mpeg, multimedia

;; This file is part of EMMS.

;; EMMS is free software; you can redistribute it and/or modify it under the
;; terms of the GNU General Public License as published by the Free Software
;; Foundation; either version 2, or (at your option) any later version.

;; EMMS is distributed in the hope that it will be useful, but WITHOUT ANY
;; WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
;; details.

;; You should have received a copy of the GNU General Public License along with
;; EMMS; see the file COPYING.  If not, write to the Free Software Foundation,
;; Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

;;; Commentary:

;; This code sends information about what music you are playing to last.fm.
;; See <URL:http://www.last.fm> and
;; <URL:http://www.audioscrobbler.net/wiki/Protocol1.1>.

;;; Sample configuration:

;; (setq emms-lastfm-username "my-user-name"
;;       emms-lastfm-password "very-secret!")

;;; Usage:

;; To activate the last.fm emms plugin, run:
;; `M-x emms-lastfm-enable'

;; To deactivate the last.fm emms plugin, run:
;; `M-x emms-lastfm-disable'

;; -----------------------------------------------------------------------

(require 'url)
(require 'emms)

(defvar emms-lastfm-username ""
  "Your last.fm username")
(defvar emms-lastfm-password ""
  "Your last.fm password")

(defconst emms-lastfm-server "http://post.audioscrobbler.com/"
  "The last.fm server responsible for the handshaking
procedure. Only for internal use.")
(defconst emms-lastfm-client-id "ems"
  "The client ID of EMMS. Don't change it!")
(defconst emms-lastfm-client-version 0.1
  "The version registered at last.fm. Don't change it!")

;; used internally
(defvar emms-lastfm-buffer nil "-- only used internally --")
(defvar emms-lastfm-process nil "-- only used internally --")
(defvar emms-lastfm-md5-challenge nil "-- only used internally --")
(defvar emms-lastfm-submit-url nil "-- only used internally --")
(defvar emms-lastfm-current-track nil "-- only used internally --")
(defvar emms-lastfm-timer nil "-- only used internally --")

(defun emms-lastfm-new-track-function ()
  "This function should run whenever a new track starts (or a
paused track resumes) and sets the track submission timer."
  (setq emms-lastfm-current-track
        (emms-playlist-current-selected-track))
  ;; Tracks should be submitted, if they played 240 secs or half of their
  ;; length, whichever comes first.
  (let ((secs (/ (emms-track-get emms-lastfm-current-track
                                 'info-playing-time)
                    2)))
    (when (> secs 240)
      (setq secs 240))
    (unless (< secs 15) ;; Skip titles shorter than 30 seconds
      (setq secs (- secs emms-playing-time))
      (unless (< secs 0)
        (setq emms-lastfm-timer
              (run-with-timer secs nil 'emms-lastfm-submit-track))))))

(defun emms-lastfm-cancel-timer ()
  "Cancels `emms-lastfm-timer' if it is running."
  (when emms-lastfm-timer
    (cancel-timer emms-lastfm-timer)
    (setq emms-lastfm-timer nil)))

(defun emms-lastfm-pause ()
  "Handles things to be done when the player is paused or
resumed."
  (if emms-player-paused-p
      ;; the player paused
      (emms-lastfm-cancel-timer)
    ;; The player resumed
    (emms-lastfm-new-track-function)))

(defun emms-lastfm (&optional ARG)
  "Start submitting the tracks you listened to to
http://www.last.fm, if ARG is positive. If ARG is negative or
zero submission of the tracks will be stopped. This applies to
the current track, too."
  (interactive "p")
  (cond
   ((not (and emms-lastfm-username emms-lastfm-password))
    (message "%s"
             (concat "EMMS: In order to activate the last.fm plugin you "
                     "first have to set both `emms-lastfm-username' and "
                     "`emms-lastfm-password'.")))
   ((not emms-playing-time-p)
    (message "%s"
             (concat "EMMS: The last.fm plugin needs the functionality "
                     "provided by `emms-playing-time'. It seems that you "
                     "disabled it explicitly in your init file using code "
                     "like this: `(emms-playing-time -1)'. Delete that "
                     "line and have a look at `emms-playing-time's doc "
                     "string.")))
   (t
    (if (and ARG (> ARG 0))
        (progn
          ;; Append it. Else the playing time could be started a bit too late.
          (add-hook 'emms-player-started-hook
                    'emms-lastfm-handshake-if-needed t)
          ;; Has to be appended, because it has to run after
          ;; `emms-playing-time-start'
          (add-hook 'emms-player-started-hook
                    'emms-lastfm-new-track-function t)
          (add-hook 'emms-player-stopped-hook
                    'emms-lastfm-cancel-timer)
          (add-hook 'emms-player-paused-hook
                    'emms-lastfm-pause)
          (message "EMMS Last.fm plugin activated."))
      (remove-hook 'emms-player-started-hook
                   'emms-lastfm-handshake-if-needed)
      (remove-hook 'emms-player-started-hook
                   'emms-lastfm-new-track-function)
      (remove-hook 'emms-player-stopped-hook
                   'emms-lastfm-cancel-timer)
      (remove-hook 'emms-player-paused-hook
                   'emms-lastfm-pause)
      (when emms-lastfm-timer (cancel-timer emms-lastfm-timer))
      (setq emms-lastfm-md5-challenge nil
            emms-lastfm-submit-url    nil
            emms-lastfm-process       nil
            emms-lastfm-current-track nil)
      (message "EMMS Last.fm plugin deactivated.")))))

(defalias 'emms-lastfm-activate 'emms-lastfm
  "Obsolete! Use `emms-lastfm-enable', `emms-lastfm-disable' or
`emms-lastfm'.")

(defun emms-lastfm-enable ()
  "Enable the emms last.fm plugin."
  (interactive)
  (emms-lastfm 1))

(defun emms-lastfm-disable ()
  "Disable the emms last.fm plugin."
  (interactive)
  (emms-lastfm -1))

(defun emms-lastfm-handshake-if-needed ()
  (when (not (and emms-lastfm-md5-challenge
                  emms-lastfm-submit-url))
    (emms-lastfm-handshake)))

(defun emms-lastfm-handshake ()
  "Handshakes with the last.fm server."
  (let ((url-request-method "GET"))
    (setq emms-lastfm-buffer
          (url-retrieve 
           (url-escape (concat emms-lastfm-server "?hs=true&p=1.1"
                               "&c=" emms-lastfm-client-id
                               "&v=" (number-to-string
                                      emms-lastfm-client-version)
                               "&u=" emms-lastfm-username))
           'emms-lastfm-handshake-sentinel))))

(defun emms-lastfm-handshake-sentinel (&rest args)
  "Parses the server reponse and inform the user if all worked
well or if an error occured."
  (save-excursion
    (set-buffer emms-lastfm-buffer)
    (goto-char (point-min))
    (re-search-forward (rx (or "UPTODATE" "UPDATE" "FAILED" "BADUSER"))
                       nil t)
    (let ((response (read-line)))
      (if (not (string-match (rx (or "UPTODATE""UPDATE")) response))
          (progn
            (cond ((string-match "FAILED" response)
                   (message "EMMS: Handshake failed: %s." response))
                  ((string-match "BADUSER" response)
                   (message "EMMS: Wrong username."))))
        (when (string-match "UPDATE" response)
          (message "EMMS: There's a new last.fm plugin version."))
        (forward-line)
        (setq emms-lastfm-md5-challenge (read-line))
        (forward-line)
        (setq emms-lastfm-submit-url (read-line))
        (message "EMMS: Handshaking with server done.")))))

(defun emms-lastfm-submit-track ()
  "Submits the current track (`emms-lastfm-current-track') to
last.fm."
  (let* ((artist (emms-track-get emms-lastfm-current-track 'info-artist))
         (title  (emms-track-get emms-lastfm-current-track 'info-title))
         (album  (emms-track-get emms-lastfm-current-track 'info-album))
         (musicbrainz-id "")
         (track-length (number-to-string
                        (emms-track-get emms-lastfm-current-track
                                        'info-playing-time)))
         (date (format-time-string "%Y-%m-%d %H:%M:%S" (current-time) t))
         (url-http-attempt-keepalives nil)
         (url-request-method "POST")
         (url-request-extra-headers
          '(("Content-type" .
             "application/x-www-form-urlencoded; charset=utf-8")))
         (url-request-data (encode-coding-string
                            (concat "u=" emms-lastfm-username
                                    "&s=" (md5 (concat
                                                (md5 emms-lastfm-password)
                                                emms-lastfm-md5-challenge))
                                    "&a[0]=" artist
                                    "&t[0]=" title
                                    "&b[0]=" album
                                    "&m[0]=" musicbrainz-id
                                    "&l[0]=" track-length
                                    "&i[0]=" date)
                            'utf-8)))
    (setq emms-lastfm-buffer
          (url-retrieve (url-escape emms-lastfm-submit-url)
                        'emms-lastfm-submission-sentinel))))

(defun emms-lastfm-submission-sentinel (&rest args)
  "Parses the server reponse and inform the user if all worked
well or if an error occured."
  (save-excursion
    (set-buffer emms-lastfm-buffer)
    (goto-char (point-min))
    (if (re-search-forward "^OK$" nil t)
        (progn
          (message "EMMS: \"%s\" submitted to last.fm."
                   (emms-track-description emms-lastfm-current-track))
          (kill-buffer emms-lastfm-buffer))
      (message "EMMS: Song couldn't be submitted to last.fm."))))


;;; Playback of lastfm:// streams

(defvar emms-lastfm-playback-base-url "http://ws.audioscrobbler.com"
  "The base URL for playing lastfm:// stream.")

(defvar emms-lastfm-playback-session nil "-- only used internally --")
(defvar emms-lastfm-playback-stream-url nil "-- only used internally --")

(defun emms-lastfm-playback-get-handshake-url ()
  (concat emms-lastfm-playback-base-url
          "/radio/handshake.php?version=" (number-to-string 
                                           emms-lastfm-client-version)
          "&platform="                    emms-lastfm-client-id
          "&username="                    emms-lastfm-username
          "&passwordmd5="                 (md5 emms-lastfm-password)
          "&debug="                       (number-to-string 9)))

(defun emms-lastfm-playback-handshake ()
  "Handshakes with the last.fm server."
  (let ((url-request-method "GET"))
    (setq emms-lastfm-buffer
          (url-retrieve (url-escape
                         (emms-lastfm-playback-get-handshake-url))
                        'emms-lastfm-playback-handshake-sentinel))))

(defun emms-lastfm-playback-handshake-sentinel (&rest args)
  (save-excursion
    (set-buffer emms-lastfm-buffer)
    (setq emms-lastfm-playback-session    (key-value "session"))
    (setq emms-lastfm-playback-stream-url (key-value "stream_url"))
    (if (and emms-lastfm-playback-session emms-lastfm-playback-stream-url)
        (message "EMMS: Handshaking for Last.fm playback successful.")
      (message "EMMS: Failed handshaking for Last.fm playback."))))

(defun emms-lastfm-playback (lastfm-url)
  "Plays the stream associated with the given Last.fm URL. (A
Last.fm URL has the form lastfm://foo/bar/baz, e.g.

  lastfm://artist/Manowar/similarartists

or

  lastfm://globaltags/metal."
  (interactive "sLast.fm URL: ")
  ;; Streamed songs must not be added to the lastfm profile
  (emms-lastfm-disable)
  (when (not (and emms-lastfm-playback-session 
                  emms-lastfm-playback-stream-url))
    (emms-lastfm-playback-handshake))
  ;; FIXME: Is there some better code to ensure that execution resumes not
  ;; before the handshake sentinel has finished???
  (let ((waits 0))
    (while (and (not (and emms-lastfm-playback-session 
                          emms-lastfm-playback-stream-url))
                (< waits 10))
      (setq waits (1+ waits))
      (sit-for 1)))
  ;; END of FIXME
  (if (and emms-lastfm-playback-session 
           emms-lastfm-playback-stream-url)
      (let ((url-request-method "GET"))
        (setq emms-lastfm-buffer
              (url-retrieve
               (url-escape
                (concat emms-lastfm-playback-base-url
                        "/radio/adjust.php?"
                        "session=" emms-lastfm-playback-session
                        "&url="    lastfm-url
                        "&debug="  (number-to-string 0)))
               'emms-lastfm-playback-sentinel)))
    (message "EMMS: Cannot play Last.fm stream.")))

(defun emms-lastfm-playback-sentinel (&rest args)
  (save-excursion
    (set-buffer emms-lastfm-buffer)
    (if (string= (key-value "response") "OK")
        (progn
          (emms-play-url emms-lastfm-playback-stream-url)
          (message "EMMS: Playing Last.fm stream."))
      (message "EMMS: Bad response from Last.fm."))))

(defun emms-lastfm-playback-similar-artists (artist)
  "Plays the similar artist radio of ARTIST."
  (interactive "sArtist: ")
  (emms-lastfm-playback (concat "lastfm://artist/"
                                artist
                                "/similarartists")))

(defun emms-lastfm-playback-global-tag (tag)
  "Plays the global tag radio of TAG."
  (interactive "sGlobal Tag: ")
  (emms-lastfm-playback (concat "lastfm://globaltags/" tag)))


;;; Utility functions

(defun read-line ()
  (buffer-substring-no-properties (line-beginning-position)
                                  (line-end-position)))

(defun key-value (key)
  "Returns the value of KEY. The buffer has to contain a
key-value list like:

foo=bar
x=17"
  (goto-char (point-min))
  (when (re-search-forward (concat "^" key "="))
    (buffer-substring-no-properties (point) (line-end-position))))

(defun url-escape (url)
  "Escapes SPACEs with %20."
  (replace-regexp-in-string " " "%20" url))

(provide 'emms-lastfm)
;;; emms-lastfm.el ends here