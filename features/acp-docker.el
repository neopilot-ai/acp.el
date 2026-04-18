;;; acp-docker.el --- Docker support -*- lexical-binding: t; -*-

;; Copyright (C) 2024 NeoPilot AI
;; Author: NeoPilot AI https://github.com/neopilot-ai
;; URL: https://github.com/neopilot-ai/acp.el
;; Version: 0.49.1
;; License: GPL-3.0+

;;; Commentary:
;;
;; Docker support for acp.el
;;
;; Usage:
;;   (require 'acp-docker)
;;   (setq acp-docker-enabled t)
;;   (setq acp-docker-image "ubuntu:latest")
;;
;; Or with Docker Compose:
;;   (setq acp-docker-compose-file "docker-compose.yml")
;;   (setq acp-docker-service "agent")

;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'json)
(require 'map)

;;;; Customization

(defgroup acp-docker nil
  "Docker support for acp.el."
  :group 'acp)

(defcustom acp-docker-enabled nil
  "Enable Docker container support for agents."
  :type 'boolean
  :group 'acp-docker)

(defcustom acp-docker-image nil
  "Docker image to use for agent containers."
  :type 'string
  :group 'acp-docker)

(defcustom acp-docker-container-name nil
  "Custom container name. If nil, a unique name is generated."
  :type 'string
  :group 'acp-docker)

(defcustom acp-docker-compose-file nil
  "Path to docker-compose.yml file."
  :type 'string
  :group 'acp-docker)

(defcustom acp-docker-service nil
  "Docker Compose service name."
  :type 'string
  :group 'acp-docker)

(defcustom acp-docker-rm-on-exit t
  "Remove container when agent session ends."
  :type 'boolean
  :group 'acp-docker)

(defcustom acp-docker-workdir "/workspace"
  "Working directory inside the container."
  :type 'string
  :group 'acp-docker)

(defcustom acp-docker-environment nil
  "Environment variables. Format: (list (cons \"VAR\" \"value\"))."
  :type '(repeat (cons string string))
  :group 'acp-docker)

(defcustom acp-docker-volumes nil
  "Volumes to mount. Format: (list \"/host:/container\")."
  :type '(repeat string)
  :group 'acp-docker)

(defcustom acp-docker-ports nil
  "Ports to expose. Format: (list \"8080:8080\")."
  :type '(repeat string)
  :group 'acp-docker)

(defcustom acp-docker-network nil
  "Docker network name."
  :type 'string
  :group 'acp-docker)

(defcustom acp-docker-extra-args nil
  "Extra docker run arguments."
  :type '(repeat string)
  :group 'acp-docker)

(defvar acp-docker--running-containers nil
  "List of running Docker containers.")

;;;; Helper Functions

(defun acp-docker--build-run-command (&key image container-name workdir volumes ports network env extra-args)
  "Build docker run command arguments."
  (let ((cmd (list "docker" "run" "-it")))
    (when container-name
      (setq cmd (append cmd (list "--name" container-name))))
    (when workdir
      (setq cmd (append cmd (list "-w" workdir))))
    (dolist (pair env)
      (setq cmd (append cmd (list "-e" (concat (car pair) "=" (cdr pair))))))
    (dolist (vol volumes)
      (setq cmd (append cmd (list "-v" vol))))
    (dolist (port ports)
      (setq cmd (append cmd (list "-p" port))))
    (when network
      (setq cmd (append cmd (list "--network" network))))
    (dolist (arg extra-args)
      (setq cmd (append cmd (list arg))))
    (setq cmd (append cmd (list image)))
    cmd))

(defun acp-docker--get-container-id (&optional service)
  "Get container ID for SERVICE."
  (when acp-docker-compose-file
    (string-trim
     (shell-command-to-string
      (format "docker compose -f %s ps -q %s 2>/dev/null"
              acp-docker-compose-file
              (or service acp-docker-service))))))

(defun acp-docker-container-running-p (&optional service)
  "Check if container is running."
  (let ((id (acp-docker--get-container-id service)))
    (and (not (string-empty-p id))
         (string-match-p "[a-f0-9]" id))))

;;;; Container Management

(defun acp-docker-start-container ()
  "Start Docker container for agent."
  (cond
   (acp-docker-compose-file
    (unless acp-docker-service
      (error "acp-docker-service required for Docker Compose"))
    (message "Starting Docker Compose service: %s" acp-docker-service)
    (let ((cmd (list "docker" "compose" "-f" acp-docker-compose-file
                     "up" "-d" "--wait" acp-docker-service)))
      (apply #'call-process (car cmd) nil nil nil (cdr cmd)))
    (dotimes (_ 30)
      (when (acp-docker-container-running-p)
        (cl-return))
      (sleep-for 0.2))
    (unless (acp-docker-container-running-p)
      (error "Container failed to start"))
    (message "Container started")
    (list "docker" "compose" "-f" acp-docker-compose-file
          "exec" "-it" acp-docker-service))

   (acp-docker-enabled
    (unless acp-docker-image
      (error "acp-docker-image required"))
    (let* ((container-name (or acp-docker-container-name
                                (format "acp-%s" (format-time-string "%Y%m%d%H%M%S"))))
           (cmd (acp-docker--build-run-command
                 :image acp-docker-image
                 :container-name container-name
                 :workdir acp-docker-workdir
                 :volumes acp-docker-volumes
                 :ports acp-docker-ports
                 :network acp-docker-network
                 :env acp-docker-environment
                 :extra-args acp-docker-extra-args)))
      (message "Starting container: %s" container-name)
      (add-to-list 'acp-docker--running-containers container-name)
      (list "docker" "exec" "-it" container-name)))

   (t
    (error "Docker not enabled. Set acp-docker-enabled or acp-docker-compose-file"))))

(defun acp-docker-stop-container ()
  "Stop and remove Docker container."
  (cond
   (acp-docker-compose-file
    (when (acp-docker-container-running-p)
      (message "Stopping service: %s" acp-docker-service)
      (call-process "docker" nil nil nil "compose"
                    "-f" acp-docker-compose-file "down")))

   (acp-docker-enabled
    (dolist (container acp-docker--running-containers)
      (message "Stopping container: %s" container)
      (call-process "docker" nil nil nil "stop" container))
    (setq acp-docker--running-containers nil))))

(defun acp-docker-resolve-path (path)
  "Resolve PATH between host and container."
  (cond
   (acp-docker-compose-file
    (let ((svc (or acp-docker-service (error "Service not set")))
          (id (acp-docker--get-container-id)))
      (when (string-empty-p id)
        (error "Container not running"))
      (string-trim
       (shell-command-to-string
        (format "docker compose -f %s exec -T %s readlink -f %s 2>/dev/null || echo %s"
                acp-docker-compose-file svc path path)))))

   (acp-docker-enabled
    (when acp-docker--running-containers
      (string-trim
       (shell-command-to-string
        (format "docker exec %s readlink -f %s 2>/dev/null || echo %s"
                (car acp-docker--running-containers) path path)))))

   (t path)))

;;;; Interactive Commands

(defun acp-docker-list-containers ()
  "List running acp containers."
  (interactive)
  (cond
   (acp-docker-compose-file
    (shell-command (format "docker compose -f %s ps" acp-docker-compose-file)))
   (acp-docker-enabled
    (shell-command "docker ps --filter name=acp-"))))

(defun acp-docker-logs (&optional service)
  "Show logs from container."
  (interactive)
  (cond
   (acp-docker-compose-file
    (compile (format "docker compose -f %s logs -f %s"
                     acp-docker-compose-file
                     (or service acp-docker-service ""))))
   (acp-docker-enabled
    (when acp-docker--running-containers
      (compile (format "docker logs -f %s"
                       (car acp-docker--running-containers)))))))

(defun acp-docker-shell ()
  "Open shell in running container."
  (interactive)
  (cond
   (acp-docker-compose-file
    (async-shell-command
     (format "docker compose -f %s exec %s /bin/sh"
             acp-docker-compose-file
             (or acp-docker-service (error "Set acp-docker-service")))))
   (acp-docker-enabled
    (when acp-docker--running-containers
      (async-shell-command
       (format "docker exec -it %s /bin/sh"
               (car acp-docker--running-containers)))))))

(provide 'acp-docker)

;;; acp-docker.el ends here
