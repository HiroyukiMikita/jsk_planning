;; utility library for eus to use pddl-planner

;; automatically load roseus and ros message packages
(ros::roseus-add-msgs "roseus")
(ros::roseus-add-msgs "std_msgs")
(ros::roseus-add-msgs "pddl_msgs")

;; class
(defclass pddl-module
  :super propertied-object
  :slots ()
  )

;; '((a . <a>) (b . <b>) (aa . <a>))
(defclass pddl-problem
  :super pddl-module
  :slots (problem-name
          initial-condition
          goal-condition
          domain-name
          metric
          obj                           ;((name . type) (name . type) ...)
          ))

(defmethod pddl-problem
  (:init (&key (name nil) (domain nil) ((:metric m) nil) ((:objects o) nil))
    (setq problem-name name)
    (setq domain-name domain)
    (setq metric m)
    (setq obj o)
    self)
  ;; accessors
  (:name (&optional name)
    (if name (setq problem-name name))
    problem-name)
  (:domain (&optional name)
    (if name (setq domain-name name))
    domain-name)
  (:metric (&optional m)
    (if m (setq metric m))
    metric)
  (:objects (&optional o)
    (if o (setq obj o))
    obj)
  (:initial-condition (&optional (condition-list nil))
    (if condition-list (setq initial-condition condition-list))
    initial-condition)
  (:goal (&optional (condition-list nil))
    (if condition-list (setq goal-condition condition-list))
    goal-condition)
  (:goal-condition (&optional (condition-list nil)) ;alias to :goal
    (send self :goal condition-list))
  (:problem-sexp ()
    `(define (problem ,problem-name)
       (:domain ,domain-name)
       (:objects
         ,@(let ((types (remove-duplicates (mapcar #'cdr obj))))
             (mapcar #'(lambda (_type)
                         (append
                          (mapcar #'car
                                  (remove-if-not
                                   #'(lambda (x)
                                       (eq (cdr x) _type))
                                   obj))
                          (list '- _type)))
                     types)))
       (:init ,initial-condition)
       (:goal (and ,@goal-condition))
       ,(if metric `(:metric ,@metric))
       ))
  (:write-to-file (file)
    (let ((sexp (send self :problem-sexp)))
      (with-open-file (f file :direction :output)
        (pprint sexp f))))
  (:print ()
    (pprint (send self :problem-sexp)))
  (:add (&key ((:initial-condition init) nil)
              ((:goal-condition goal) nil)
              ((:metric m) nil)
              ((:objects o) nil))
    (if init (push init initial-condition))
    (if goal (push goal goal-condition))
    (if m (push m metric))
    (if o (push o obj))
    self)
  (:ros-message ()
    (let ((msg
           (instance pddl_msgs::PDDLProblem :init
              :name (string problem-name)
              :domain (string domain-name)
              :objects (mapcar #'(lambda (x)
                                   (instance pddl_msgs::PDDLObject
                                             :init
                                             :type (string (cdr x))
                                             :name (string (car x))))
                               obj)
              ;;we need to avoid `init' slot because of roseus naming rule
              :initial (mapcar #'(lambda (i) (format nil "~A" i))
                               initial-condition)
              :goal (format nil "~A" `(and ,@goal-condition))
              )))
      (if metric (send msg :metric (list->simple-string metric)))
      msg))
  )

(defclass pddl-domain
  :super pddl-module
  :slots (domain-name
          requirements
          types
          constants
          predicates
          functions
          action)
  )
(defmethod pddl-domain
  (:init (&key (name nil) ((:requirements req) nil) (file nil))
    (if name (setq domain-name name))
    (if req (setq requirements req))
    self)
  (:name (&optional n)
    (if n (setq domain-name n))
    domain-name)
  (:requirements (&optional req)
    (if req (setq requirements req))
    requirements)
  (:types (&optional typ)
    (if typ (setq types typ))
    types)
  (:constants (&optional con)
    (if con (setq constants con))
    constants)
  (:predicates (&optional pre) ;;;(at-robby ?r - room) -> (at-robby (?r room))
                               ;;;(at ?b - ball ?r - room) -> (at (?b ball) (?r room)) ;; this is not implemented
    (if pre (setq predicates pre))
    predicates)
  (:functions (&optional fnc)
    (if fnc (setq functions fnc))
    functions)
  (:action (&optional ac)
    (if ac (setq action ac))
    action)
  (:add (&key
         ((:requirements req) nil)
         ((:types typ) nil)
         ((:constants con) nil)
         ((:predicates pre) nil)
         ((:functions fnc) nil)
         ((:action ac) nil))
    (if req (setq requirements (append requirements (list req))))
    (if typ (setq types        (append types        (list typ))))
    (if con (setq constants    (append constants    (list con))))
    (if pre (setq predicates   (append predicates   (list pre))))
    (if fnc (setq functions    (append functions    (list fnc))))
    (if ac  (setq action       (append action       (list ac))))
    self)
  (:domain-sexp ()
    `(define (domain ,domain-name)
       (:requirements ,@requirements)
       (:types ,@types)
       (:constants ,@constants)
       (:predicates ,@predicates)
       (:functions ,@functions)
       ,@(send-all action :action-sexp)
       ))
  (:print ()
    (pprint (send self :domain-sexp)))
  (:write-to-file (fname)
    (with-open-file (f fname :direction :output)
      (pprint (send self :domain-sexp) f)))
  (:ros-message ()
    (instance pddl_msgs::PDDLDomain :init
              :name (string domain-name)
              :requirements (list->simple-string requirements)
              :types (mapcar #'string types)
              :constants (mapcar #'string constants)
              :predicates
              (mapcar
               #'(lambda (x) (format nil "~A" x))
               predicates)
              :functions
              (mapcar
               #'(lambda (x) (format nil "~A" x))
               functions)
#|
(append (list (car predicates))
        (mapcar #'(lambda (x) (if (= (length x) 1) (list (car x)) (append (butlast x) '(-) (last x)))) (cdr predicates)))
|#
              :actions (send-all action :ros-message)))
  )

(defclass pddl-action
  :super pddl-module
  :slots (name
          parameters
          precondition
          effect)
  )
(defmethod pddl-action
  (:init (&key ((:name n) nil)
               ((:parameters par) nil)
               ((:precondition pre) nil)
               ((:effect ef) nil))
    (if n (setq name n))
    (if pre (setq precondition pre))
    (if par (setq parameters par))
    (if ef (setq effect ef))
    self)
  (:name (&optional n)
    (if n (setq name n))
    name)
  (:parameters (&optional par)  ;;; (?obj0 - type0 ?obj1 - type1) -> ((?obj0 type0) (?obj1 type1))
                                ;;; (?obj0 ?obj1 - type0 ?obj2 - type1) -> ((?obj ?obj type) (?obj2 type1))
                                ;;; (?obj0 ?obj1) -> ((?obj0) (?obj1))
    (if par (setq parameters par))
    parameters)
  (:precondition (&optional pre)
    (if pre (setq precondition pre))
    precondition)
  (:effect (&optional ef)
    (if ef (setq effect ef))
    effect)
  (:add (&key ((:effect ef) nil)
              ((:parameters par) nil)
              ((:precondition pre) nil)
              )
    (if ef  (setq effect       (append effect       (list ef))))
    (if par (setq parameters   (append parameters   (list par))))
    (if pre (setq precondition (append precondition (list par))))
    self)
  (:action-sexp ()
    `(:action ,name
       :parameters ,(flatten (mapcar #'(lambda (x)
                                         (if (= (length x) 1)
                                             (list (car x))
                                           (append (butlast x) '(-) (last x))))
                                     parameters))
       :precondition (and ,@precondition)
       :effect (and ,@effect)))
  (:ros-message ()
    (instance pddl_msgs::PDDLAction :init
              :name (string name)
              :parameters
              (if parameters
                  (list->simple-string
                   (list (flatten (mapcar #'(lambda (x)
                                              (if (= (length x) 1)
                                                  (list (car x))
                                                (append (butlast x) '(-) (last x))))
                                          parameters))))
                "()")
              :precondition
              (format nil "~A" `(and ,@precondition))
              :effect
              (format nil "~A" `(and ,@effect))))
  )

;; macro for define domain and problem
(defmacro define-pddl-problem (sym
                               &key
                               name domain objects
                               initial-condition goal-condition)
  (let ((tmp (gensym)))
    `(setq ,sym (let ((,tmp (instance pddl-problem :init)))
                  (send ,tmp :name ',name)
                  (send ,tmp :domain ',domain)
                  (send ,tmp :objects ',objects)
                  (send ,tmp :initial-condition ',initial-condition)
                  (send ,tmp :goal ',goal-condition)
                  ,tmp))))

(defun make-pddl-action (action-spec)
  (destructuring-bind
      (name &key parameters precondition effect)
      action-spec
    (instance pddl-action :init
              :name (string name)
              :parameters parameters
              :precondition precondition
              :effect effect)))

(defmacro define-pddl-domain (sym
                              &key
                              name requirements
                              types predicates
                              actions)
  (let ((tmp (gensym)))
    `(setq ,sym (let ((,tmp (instance pddl-domain :init)))
                  (send ,tmp :name ',name)
                  (send ,tmp :requirements ',requirements)
                  (send ,tmp :types ',types)
                  (send ,tmp :predicates ',predicates)
                  ;; build actions
                  (send ,tmp :action
                        (mapcar #'make-pddl-action ',actions))
                  ,tmp))))

;; function for parse planning result


;; utility
(defun list->simple-string (x)
  "this function is not cool...."
  (let ((str (format nil "~A" x)))
    (subseq str 1 (1- (length str))))) ; remove ( and )

(defclass pddl-state
  :super pddl-module
  :slots (name
          domain
          states
          actions
          objects)
  )

(defmethod pddl-state
  (:init (&key ((:name n) nil)
               ((:domain dm) nil)
               ((:initial-state st) nil)
               ((:actions ac) nil)
               ((:objects obj) nil)
               )
    (if n (setq name n))
    (send self :domain dm)
    (send self :initial-state st)
    (if ac (setq actions ac))
    (send self :objects obj)
    self)
  (:name (&optional n)
    (if n (setq name n))
    name)
  (:domain (&optional dm)
    (when dm
      (setq domain dm)
      (send self :add-constants))
    domain)
  (:initial-state (&optional st)
    (when st
      (let (tmp-st)
        (dolist (i st)
          (unless (equal (car i) 'not)
            (push i tmp-st)))
        (setq states (list tmp-st))))
    states)
  (:actions (&optional ac)
    (when ac
      (setq actions ac)
      (send self :generate-states))
    actions)
  (:objects (&optional obj)
    (when obj
      (setq objects obj)
      (if domain
          (send self :add-constants)))
    objects)
  (:states (&rest args)
    (forward-message-to states args))
  (:add-constants ()
    (let (obj (cnst (send domain :constants)) sym)
      (when cnst
        (let ((count 0) (max-count (length cnst)))
          (while (< count max-count)
            (let ((elem (elt cnst count)))
              (if (equal elem '-)
                  (progn
                    (incf count)
                    (let ((type (elt cnst count)))
                      (setq obj (append obj (mapcar #'(lambda(x) (cons x type)) sym))))
                    (setq sym nil))
                (push elem sym))
              (incf count)))
          (setq objects (union obj objects :test #'equal))))))
  (:add-action (ac)
    (when ac
      (setq actions (append actions (list ac)))
      (setq states (append states (list (send self :apply-action (car (last states)) ac)))))
    actions)
  (:generate-states ()
    (when (and states actions)
      (setq states (list (car states)))
      (let ((tmp-st (car states)))
        (dolist (act actions)
          (setq tmp-st (send self :apply-action tmp-st act))
          (push tmp-st states))
        (setq states (nreverse states))))
    )
  (:check-type ()
    ;;TODO
    )
  (:check-condition (st act)
    (let ((action (find-if #'(lambda (x) (equal (car act) (intern (string-upcase (send x :name))))) (send domain :action)))
          param pcond)
      (unless action
        (return-from :check-condition nil))
      (setq param (list (flatten (mapcar #'(lambda(x) (butlast x 1)) (send action :parameters))) (cdr act))
            pcond (send action :precondition))
      (null (some #'null
                  (mapcar #'(lambda (p)
                              (send self :check-state st p param))
                          pcond)))
      ))
  (:check-state (st s param)
    (let ((ss (mapcar #'(lambda(x)
                          (let ((pos (position x (car param))))
                            (if pos
                                (elt (cadr param) pos)
                              x)))
                      s)))
      (case (car ss)
        ('not
         (if (send self :check-state st (cadr ss) param)
             nil
           t))
        ('and
         (let ((ret (mapcar #'(lambda(x)
                                (send self :check-state st x param))
                            (cdr ss))))
           (null (some #'null ret))))
        ('or
         (let ((ret (mapcar #'(lambda(x)
                                (send self :check-state st x param))
                            (cdr ss))))
           (null (every #'null ret))))
        ('exists
         (let* ((v (cadr ss))
                (ret (mapcar #'(lambda(obj)
                                 (if (equal (caddr v) (cdr obj))
                                     (multiple-value-bind (va ar) param
                                       (send self :check-state st (caddr ss) (list (append va (list (car v))) (append ar (list (car obj))))))
                                   nil)
                                 )
                             objects)))
           (null (every #'null ret))))
        ('forall
         (let* ((v (cadr ss))
                (ret (mapcar #'(lambda(obj)
                                 (if (equal (caddr v) (cdr obj))
                                     (multiple-value-bind (va ar) param
                                       (send self :check-state st (caddr ss) (list (append va (list (car v))) (append ar (list (car obj))))))
                                   t)
                                 )
                             objects)))
           (null (some #'null ret))))
        ('when
         (if (send self :check-state st (cadr ss) param)
             (send self :check-state st (caddr ss) param)
           t))
        ('=
         (equal (cadr ss) (caddr ss)))
        (t
         (if (member ss st :test #'equal)
             t
           nil))
        )
      ))
  (:apply-action (st act)
    (if (send self :check-condition st act)
        (let ((action (find-if #'(lambda (x) (equal (car act) (intern (string-upcase (send x :name))))) (send domain :action)))
              param effect (tmp-st st))
          (unless action
            (return-from :apply-action nil))
          (setq param (list (flatten (mapcar #'(lambda(x) (butlast x 1)) (send action :parameters))) (cdr act))
                effect (send action :effect))
          (dolist (e effect)
            (setq tmp-st (send self :change-state tmp-st e param)))
          tmp-st)
      nil)
    )
  (:change-state (st e param)
    (let ((ee (mapcar #'(lambda(x)
                          (let ((pos (position x (car param))))
                            (if pos
                                (elt (cadr param) pos)
                              x)))
                      e))
          (tmp-st st))
      (case (car ee)
        ('increase
         st)
        ('decrease
         st)
        ('not
         (let ((dif (mapcar #'(lambda(x)
                                (let ((pos (position x (car param))))
                                  (if pos
                                      (elt (cadr param) pos)
                                    x)))
                            (cadr ee))))
           (set-difference st (list dif) :test #'equal)))
        ('and
         (dolist (eff (cdr ee))
           (setq tmp-st (send self :change-state tmp-st eff param)))
         tmp-st)
        ('forall
         (let ((v (cadr ee)))
           (dolist (obj objects)
             (when (equal (caddr v) (cdr obj))
               (multiple-value-bind (va ar) param
                 (setq tmp-st (send self :change-state tmp-st (caddr ee) (list (append va (list (car v))) (append ar (list (car obj)))))))))
           tmp-st))
        ('when
         (case (caadr ee)
           ('=
            (if (send self :check-state st (cadr ee) param)
                (send self :change-state st (caddr ee) param)
              st))
           ('not
            (if (null (send self :check-state st (car (cdadr ee)) param))
                (send self :change-state st (caddr ee) param)
              st))
           (t
            (if (send self :check-state st (cadr ee) param)
                (send self :change-state st (caddr ee) param)
              st))))
        (t
         (union st (list ee) :test #'equal)
         )
        )
      ))
  )

(provide :eus-pddl)
