;;; acp-docker.el --- Docker support -*- lexical-binding: t; -*-

;; Copyright (C) 2024 NeoPilot AI

;; Author: NeoPilot AI https://github.com/neopilot-ai
;; URL: https://github.com/neopilot-ai/acp.el
;; Version: 0.49.1

;; This package is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This package is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This file provides Docker support for running agents in containers.
;;
;; Features:
;; - Run agents in Docker containers
;; - Docker Compose support
;; - Container lifecycle management
;; - Path resolution between host and container
;;
;; Usage:
;;   (require 'acp-docker)
;;   (setq acp-docker-enabled t)
;;   (setq acp-docker-image "ubuntu:latest")
;;
;; Or use Docker Compose:
;;   (setq acp-docker-compose-file "docker-compose.yml")
;;   (setq acp-docker-service "agent")

;;; Code:

(require 'json)
(require 'map)

(defgroup acp-docker nil
  "Docker support for acp.el"
  :group 'acp
  :prefix "acp-docker-")

(defcustom acp-docker-enabled nil
  "Enable Docker container support for agents."
  :type 'boolean
  :group 'acp-docker)

(defcustom acp-docker-image nil
  "Docker image to use for agent containers.
Used when `acp-docker-enabled' is non-nil."
  :type 'string
  :group 'acp-docker)

(defcustom acp-docker-container-name nil
  "Custom container name for agent.
If nil, a unique name will be generated."
  :type 'string
  :group 'acp-docker)

(defcustom acp-docker-compose-file nil
  "Path to docker-compose.yml file.
If set, Docker Compose will be used instead of plain Docker."
  :type 'string
  :group 'acp-docker)

(defcustom acp-docker-service nil
  "Docker Compose service name to use.
Required when using Docker Compose."
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
  "Environment variables to pass to container.
Format: '((\"VAR\" . \"value\") (\"VAR2\" . \"value2\"))"
  :type '(repeat (cons string string))
  :group 'acp-docker)

(defcustom acp-docker-volumes nil
  "Volumes to mount into container.
Format: '(\"/host/path:/container/path\" ...)"
  :type '(repeat string)
  :group 'acp-docker)

(defcustom acp-docker-ports nil
  "Ports to expose from container.
Format: '(\"8080:8080\" ...)"
  :type '(repeat string)
  :group 'acp-docker)

(defcustom acp-docker-network nil
  "Docker network to connect container to."
  :type 'string
  :group 'acp-docker)

(defcustom acp-docker-extra-args nil
  "Extra arguments to pass to docker run.
Format: '(\"--gpu\" \"all\" \"--rm\" ...)"
  :type '(repeat string)
  :group 'acp-docker)

(defvar acp-docker--running-containers nil
  "List of currently running Docker containers.")

(cl-defun acp-docker--build-run-command (&key image container-name workdir volumes ports network env extra-args)
  "Build docker run command.
Returns list of command arguments."
  (let ((cmd (list "docker" "run" "-it" "--rm")))
    
    ;; Container name
    (when container-name
      (setq cmd (append cmd (list "--name" container-name))))
    
    ;; Working directory
    (when workdir
      (setq cmd (append cmd (list "-w" workdir))))
    
    ;; Environment variables
    (dolist (pair env)
      (setq cmd (append cmd (list "-e" (concat (car pair) "=" (cdr pair))))))
    
    ;; Volumes
    (dolist (volume volumes)
      (setq cmd (append cmd (list "-v" volume))))
    
    ;; Ports
    (dolist (port ports)
      (setq cmd (append cmd (list "-p" port))))
    
    ;; Network
    (when network
      (setq cmd (append cmd (list "--network" network))))
    
    ;; Extra args
    (when extra-args
      (setq cmd (append cmd extra-args)))
    
    ;; Interactive mode
    (setq cmd (append cmd (list "-i")))
    
    ;; Image and command
    (setq cmd (append cmd (list image)))
    
    cmd))

(cl-defun acp-docker--build-compose-command (&key compose-file service workdir env volumes ports network extra-args action)
  "Build docker compose command.
ACTION can be 'up, 'down, 'exec, 'logs."
  (let ((cmd (list "docker" "compose" "-f" compose-file)))
    
    (pcase action
      ('up
       (setq cmd (append cmd (list "up" "-d" "--wait")))
       (when service
         (setq cmd (append cmd (list service)))))
      
      ('down
       (setq cmd (append cmd (list "down"))))
      
      ('exec
       (setq cmd (append cmd (list "exec" "-it" service)))
       (when workdir
         (setq cmd (append cmd (list "-w" workdir))))
       ;; Environment variables
       (dolist (pair env)
         (setq cmd (append cmd (list "-e" (concat (car pair) "=" (cdr pair))))))
       ;; Additional args passed as command
       )
      
      ('logs
       (setq cmd (append cmd (list "logs" "-f" service)))))
    
    cmd))

(defun acp-docker--get-compose-project ()
  "Get Docker Compose project name from compose file."
  (when acp-docker-compose-file
    (let* ((dir (file-name-directory (expand-file-name acp-docker-compose-file)))
           (name (file-name-nondirectory (directory-file-name dir))))
      (or (getenv "COMPOSE_PROJECT_NAME") name))))

(defun acp-docker--get-container-id (service)
  "Get container ID for SERVICE."
  (when acp-docker-compose-file
    (string-trim
     (shell-command-to-string
      (format "docker compose -f %s ps -q %s 2>/dev/null"
              acp-docker-compose-file service)))))

(defun acp-docker-container-running-p (&optional service)
  "Check if container is running.
SERVICE defaults to `acp-docker-service'."
  (let* ((svc (or service acp-docker-service))
         (container-id (acp-docker--get-container-id svc)))
    (and (not (string-empty-p container-id))
         (string-match-p "[a-f0-9]" container-id))))

(defun acp-docker-start-container ()
  "Start Docker container for agent.
Returns the command to run the agent inside the container."
  (cond
   ;; Docker Compose mode
   (acp-docker-compose-file
    (unless acp-docker-service
      (error "acp-docker-service is required when using Docker Compose"))
    
    (message "Starting Docker Compose service: %s" acp-docker-service)
    
    ;; Start the service
    (let ((cmd (acp-docker--build-compose-command
                :compose-file acp-docker-compose-file
                :service acp-docker-service
                :workdir acp-docker-workdir
                :env acp-docker-environment
                :action 'up)))
      (apply #'call-process (car cmd) nil nil nil (cdr cmd)))
    
    ;; Wait for container to be ready
    (let ((max-attempts 30)
          (attempt 0))
      (while (and (< attempt max-attempts)
                  (not (acp-docker-container-running-p)))
        (sleep-for 0.2)
        (setq attempt (1+ attempt))))
    
    (when (not (acp-docker-container-running-p))
      (error "Container failed to start"))
    
    (message "Container started successfully")
    
    ;; Return exec command
    (list "docker" "compose" "-f" acp-docker-compose-file
          "exec" "-it" acp-docker-service))
   
   ;; Plain Docker mode
   (acp-docker-enabled
    (unless acp-docker-image
      (error "acp-docker-image is required when Docker is enabled"))
    
    (let* ((container-name (or acp-docker-container-name
                               (format "acp-%s"
                                       (format-time-string "%Y%m%d%H%M%S"))))
      
      (message "Starting Docker container: %s" container-name)
      
      (let ((cmd (acp-docker--build-run-command
                  :image acp-docker-image
                  :container-name container-name
                  :workdir acp-docker-workdir
                  :volumes acp-docker-volumes
                  :ports acp-docker-ports
                  :network acp-docker-network
                  :env acp-docker-environment
                  :extra-args acp-docker-extra-args)))
        
        ;; Start container in background and get ID
        (let ((container-id
               (string-trim
                (shell-command-to-string
                 (format "%s &> /dev/null & echo $!"
                         (mapconcat #'shell-quote-argument cmd " "))))))
          
          (when (string-match-p "^[0-9]+$" container-id)
            (add-to-list 'acp-docker--running-containers container-name))
          
          (message "Container %s started" container-name)
          
          ;; Return docker exec command
          (list "docker" "exec" "-it" container-name))))
   
   (t
    (error "Docker is not enabled. Set acp-docker-enabled to t"))))

(defun acp-docker-stop-container ()
  "Stop and remove Docker container."
  (cond
   (acp-docker-compose-file
    (when (acp-docker-container-running-p)
      (message "Stopping Docker Compose service: %s" acp-docker-service)
      (call-process "docker" nil nil nil "compose"
                    "-f" acp-docker-compose-file
                    "down")))
   
   (acp-docker-enabled
    (dolist (container acp-docker--running-containers)
      (message "Stopping container: %s" container)
      (call-process "docker" nil nil nil "stop" container))
    (setq acp-docker--running-containers nil))))

(defun acp-docker-resolve-path (path)
  "Resolve PATH between host and container.
Converts container paths to host paths and vice versa."
  (cond
   (acp-docker-compose-file
    (let* ((svc (or acp-docker-service (error "Service not set")))
           (container-id (acp-docker--get-container-id svc)))
      (when (string-empty-p container-id)
        (error "Container not running"))
      
      ;; Try to resolve using docker compose exec
      (string-trim
       (shell-command-to-string
        (format "docker compose -f %s exec -T %s readlink -f %s 2>/dev/null || echo %s"
                acp-docker-compose-file svc path path)))))
   
   (acp-docker-enabled
    (when acp-docker--running-containers
      (let ((container (car acp-docker--running-containers)))
        (string-trim
         (shell-command-to-string
          (format "docker exec %s readlink -f %s 2>/dev/null || echo %s"
                  container path path))))))
   
   (t
    path)))

(defun acp-docker-list-containers ()
  "List running acp containers."
  (interactive)
  (cond
   (acp-docker-compose-file
    (when acp-docker-compose-file
      (shell-command "docker compose -f docker-compose.yml ps")))
   
   (acp-docker-enabled
    (shell-command "docker ps --filter \"name=acp-\""))))

(defun acp-docker-logs (&optional service)
  "Show logs from container.
SERVICE defaults to `acp-docker-service'."
  (interactive)
  (cond
   (acp-docker-compose-file
    (let ((svc (or service acp-docker-service)))
      (compile (format "docker compose -f %s logs -f %s"
                       acp-docker-compose-file svc))))
   
   (acp-docker-enabled
    (when acp-docker--running-containers
      (compile (format "docker logs -f %s"
                       (car acp-docker--running-containers))))))

(defun acp-docker-shell ()
  "Open shell in running container."
  (interactive)
  (cond
   (acp-docker-compose-file
    (let ((svc (or acp-docker-service (error "Service not set"))))
      (async-shell-command
       (format "docker compose -f %s exec %s /bin/sh"
               acp-docker-compose-file svc))))
   
   (acp-docker-enabled
    (when acp-docker--running-containers
      (async-shell-command
       (format "docker exec -it %s /bin/sh"
               (car acp-docker--running-containers))))))

;; Register as a feature
(provide 'acp-docker)

;;; acp-docker.el ends here
