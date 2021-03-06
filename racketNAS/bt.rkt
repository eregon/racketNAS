#lang racket/base

(provide main)
  
(require "bm-args.rkt") 
(require "bm-results.rkt") 
(require "rand-generator.rkt")
(require "timer.rkt")
(require "parallel-utils.rkt")
(require "debug.rkt")
(require "macros.rkt")
(require racket/match)
(require (for-syntax scheme/base))
(require (for-syntax "macros.rkt"))

(require (only-in scheme/flonum make-flvector 
                                make-shared-flvector 
                                shared-flvector
                                flvector
                                ))

(require (rename-in scheme/unsafe/ops
                    [unsafe-vector-ref vr] 
                    [unsafe-vector-set! vs!]
                    [unsafe-flvector-ref fr] 
                    [unsafe-flvector-set! f!]
))
 
(define (get-class-size CLASS)
  (case CLASS 
    [(#\S) (values  12  0.01    60)]
    [(#\W) (values  24  0.0008 200)]
    [(#\A) (values  64  0.0008 200)]
    [(#\B) (values  102 0.0003 200)]
    [(#\C) (values  162 0.0001 200)]
    [else (error "Unknown class")]))

(define (get-verify-values class)
  (case class
    [(#\S) (values
        (flvector
       1.7034283709541311E-01
       1.2975252070034097E-02
       3.2527926989486055E-02
       2.6436421275166801E-02
       1.9211784131744430E-01)
        (flvector
       4.9976913345811579E-04
       4.5195666782961927E-05
       7.3973765172921357E-05
       7.3821238632439731E-05
       8.9269630987491446E-04)
       0.01)]
    [(#\W) (values
        (flvector
       0.1125590409344E+03
       0.1180007595731E+02
       0.2710329767846E+02
       0.2469174937669E+02
       0.2638427874317E+03)

        (flvector
       0.4419655736008E+01
       0.4638531260002
       0.1011551749967E+01
       0.9235878729944
       0.1018045837718E+02)
       0.0008)]
    [(#\A) (values
        (flvector
       1.0806346714637264E+02
       1.1319730901220813E+01
       2.5974354511582465E+01
       2.3665622544678910E+01
       2.5278963211748344E+02)
        (flvector
       4.2348416040525025
       4.4390282496995698E-01
       9.6692480136345650E-01
       8.8302063039765474E-01
       9.7379901770829278)
       0.0008)]
    [(#\B) (values
        (flvector
       1.4233597229287254E+03
       9.9330522590150238E+01
       3.5646025644535285E+02
       3.2485447959084092E+02
       3.2707541254659363E+03)
        (flvector
       5.2969847140936856E+01
       4.4632896115670668
       1.3122573342210174E+01
       1.2006925323559144E+01
       1.2459576151035986E+02)
       0.0003)]
    [(#\C) (values
        (flvector
       0.62398116551764615E+04
       0.50793239190423964E+03
       0.15423530093013596E+04
       0.13302387929291190E+04
       0.11604087428436455E+05)
        (flvector
       0.16462008369091265E+03
       0.11497107903824313E+02
       0.41207446207461508E+02
       0.37087651059694167E+02
       0.36211053051841265E+03)
       0.0001)]
    [else (values
        (make-flvector 5 1.0)
        (make-flvector 5 1.0)
        0.00001)]))


 (define ce (shared-flvector 
     2.0 1.0 2.0 2.0 5.0 
     0.0 0.0 2.0 2.0 4.0 
     0.0 0.0 0.0 0.0 3.0 
     4.0 0.0 0.0 0.0 2.0 
     5.0 1.0 0.0 0.0 0.1 
     3.0 2.0 2.0 2.0 0.4 
     0.5 3.0 3.0 3.0 0.3 
     0.02 0.01 0.04 0.03 0.05 
     0.01 0.03 0.03 0.05 0.04 
     0.03 0.02 0.05 0.04 0.03 
     0.5 0.4 0.3 0.2 0.1 
     0.4 0.3 0.5 0.1 0.3 
     0.3 0.5 0.4 0.3 0.2))

(define (main . argv) 
  (let ([args (parse-cmd-line-args argv "Conjugate Gradient")]) 
    (run-benchmark args)))

(define make-fxvector make-vector)

(define (run-benchmark args) 
  (let ([bmname "BT"]
        [CLASS (BMArgs-class args)]
        [num-threads (BMArgs-num-threads args)]
        [serial (BMArgs-serial args)])

  (let-values ([(problem_size dt_default niter_default) (get-class-size CLASS)])
    (let* (
          [niter niter_default]
          ;[niter 10]
          [dt dt_default]
          [IMAX problem_size]
          [JMAX problem_size]
          [KMAX problem_size]
          ;[grid_points (make-fxvector 3 problem_size)]
          [nx problem_size]
          [ny problem_size]
          [nz problem_size]
          [nx2 (- problem_size 2)]
          [ny2 (- problem_size 2)]
          [nz2 (- problem_size 2)]
          [dnxm1 (/ 1.0 (- problem_size 1))]
          [dnym1 (/ 1.0 (- problem_size 1))]
          [dnzm1 (/ 1.0 (- problem_size 1))]

          [isize (- problem_size 1)]
          [jsize (- problem_size 1)]
          [ksize (- problem_size 1)]

          [jsize1 (add1 IMAX)]
          [ksize1 (* (add1 IMAX) (add1 JMAX))]

          [isize2 5]
          [jsize2 (* 5 (add1 IMAX))]
          [ksize2 (* 5 (add1 IMAX) (add1 JMAX))]

          [jsize3 (+ problem_size 2)]
          [isize4 5]
          [jsize4 (* 5 5)]
          [ksize4 (* 5 5 3)]
          [s1 (* ksize1 KMAX)]
          [s2 (* ksize2 KMAX)]
          [s3 (* ksize4 (add1 problem_size))]
          [s4 (* jsize4 (add1 problem_size))]
          [us      (make-shared-flvector s1 0.0)]
          [vs      (make-shared-flvector s1 0.0)]
          [ws      (make-shared-flvector s1 0.0)]
          [qs      (make-shared-flvector s1 0.0)]
          [rho_i   (make-shared-flvector s1 0.0)]
          [square  (make-shared-flvector s1 0.0)]

          [u       (make-shared-flvector s2 0.0)]
          [rhs     (make-shared-flvector s2 0.0)]
          [forcing (make-shared-flvector s2 0.0)]

          [lhs     (make-shared-flvector s3 0.0)]
          [fjac    (make-shared-flvector s4 0.0)]
          [njac    (make-shared-flvector s4 0.0)]

          [cv      (make-shared-flvector (+ problem_size 2) 0.0)]
          [cuf     (make-shared-flvector (+ problem_size 2) 0.0)]
          [q       (make-shared-flvector (+ problem_size 2) 0.0)]

          [ue      (make-shared-flvector (* 5 jsize3) 0.0)]
          [buf     (make-shared-flvector (* 5 jsize3) 0.0)]

          [c1      1.4]
          [c2      0.4]
          [c3      0.1]
          [c4      1.0]
          [c5      1.4]
          [c1c2    (* 1.4 0.4)]
          [c1c5    (* 1.4 1.4)]
          [c3c4    (* 0.1 1.0)]
          [c1345   (* c1 c3 c4 c5)]
          [tx1     (/ 1.0 (flsqr dnxm1))]
          [ty1     (/ 1.0 (flsqr dnym1))]
          [tz1     (/ 1.0 (flsqr dnzm1))]
          [tx2     (/ 1.0 (* 2.0 dnxm1))]
          [ty2     (/ 1.0 (* 2.0 dnym1))]
          [tz2     (/ 1.0 (* 2.0 dnzm1))]
          [tx3     (/ 1.0 dnxm1)]
          [ty3     (/ 1.0 dnym1)]
          [tz3     (/ 1.0 dnzm1)]
          [c3c4tx3 (* c3c4 tx3)]
          [c3c4ty3 (* c3c4 ty3)]
          [c3c4tz3 (* c3c4 tz3)]
          [con43   (/ 4.0 3.0)]
          [conz1   (- 1.0 c1c5)]
          [con16   (/ 1.0 6.0)]
          [xxcon1  (* c3c4tx3 con43 tx3)]
          [xxcon2  (* c3c4tx3       tx3)]
          [xxcon3  (* c3c4tx3 conz1 tx3)]
          [xxcon4  (* c3c4tx3 con16 tx3)]
          [xxcon5  (* c3c4tx3 c1c5  tx3)]
          [yycon1  (* c3c4ty3 con43 ty3)]
          [yycon2  (* c3c4ty3       ty3)]
          [yycon3  (* c3c4ty3 conz1 ty3)]
          [yycon4  (* c3c4ty3 con16 ty3)]
          [yycon5  (* c3c4ty3 c1c5  ty3)]
          [zzcon1  (* c3c4tz3 con43 tz3)]
          [zzcon2  (* c3c4tz3       tz3)]
          [zzcon3  (* c3c4tz3 conz1 tz3)]
          [zzcon4  (* c3c4tz3 con16 tz3)]
          [zzcon5  (* c3c4tz3 c1c5  tz3)]
          [dx1tx1  (* 0.75 tx1)]
          [dx2tx1  (* 0.75 tx1)]
          [dx3tx1  (* 0.75 tx1)]
          [dx4tx1  (* 0.75 tx1)]
          [dx5tx1  (* 0.75 tx1)]
          [dy1ty1  (* 0.75 ty1)]
          [dy2ty1  (* 0.75 ty1)]
          [dy3ty1  (* 0.75 ty1)]
          [dy4ty1  (* 0.75 ty1)]
          [dy5ty1  (* 0.75 ty1)]
          [dz1tz1  (* 1.0 tz1)]
          [dz2tz1  (* 1.0 tz1)]
          [dz3tz1  (* 1.0 tz1)]
          [dz4tz1  (* 1.0 tz1)]
          [dz5tz1  (* 1.0 tz1)]
          [dtdx1tx1  (* dt dx1tx1)]
          [dtdx2tx1  (* dt dx2tx1)]
          [dtdx3tx1  (* dt dx3tx1)]
          [dtdx4tx1  (* dt dx4tx1)]
          [dtdx5tx1  (* dt dx5tx1)]
          [dtdy1ty1  (* dt dy1ty1)]
          [dtdy2ty1  (* dt dy2ty1)]
          [dtdy3ty1  (* dt dy3ty1)]
          [dtdy4ty1  (* dt dy4ty1)]
          [dtdy5ty1  (* dt dy5ty1)]
          [dtdz1tz1  (* dt dz1tz1)]
          [dtdz2tz1  (* dt dz2tz1)]
          [dtdz3tz1  (* dt dz3tz1)]
          [dtdz4tz1  (* dt dz4tz1)]
          [dtdz5tz1  (* dt dz5tz1)]
          [dx1 0.75]
          [dx2 0.75]
          [dx3 0.75]
          [dx4 0.75]
          [dx5 0.75]
          [dy1 0.75]
          [dy2 0.75]
          [dy3 0.75]
          [dy4 0.75]
          [dy5 0.75]
          [dz1 1.00]
          [dz2 1.00]
          [dz3 1.00]
          [dz4 1.00]
          [dz5 1.00]
          [dssp    (* 0.25 (flmax* dx1 dy1 dz1))]
          [dttx1 (* dt tx1)]
          [dttx2 (* dt tx2)]
          [dtty1 (* dt ty1)]
          [dtty2 (* dt ty2)]
          [dttz1 (* dt tz1)]
          [dttz2 (* dt tz2)]
          [c2dttx1 (* 2.0 dttx1)]
          [c2dtty1 (* 2.0 dtty1)]
          [c2dttz1 (* 2.0 dttz1)]
          [dxmax (flmax dx3 dx4)]
          [dymax (flmax dy2 dy4)]
          [dzmax (flmax dz2 dz3)]
          [dtdssp (* dt dssp)]
          [comz1 dtdssp]
          [comz4 (* 4.0 dtdssp)]
          [comz5 (* 5.0 dtdssp)]
          [comz6 (* 6.0 dtdssp)]
          [civ 2.5]
)
(define (compute_rhs_thunk)
(compute_rhs (CGSingle) isize2 jsize2 ksize2 jsize1 ksize1 u us vs ws rho_i square qs 
c1c2 rhs forcing nx2 ny2 nz2 c1 c2 dssp
    tx2 ty2 tz2 con43 dt
    dx1tx1 dx2tx1 dx3tx1 dx4tx1 dx5tx1
    xxcon2 xxcon3 xxcon4 xxcon5
    dy1ty1 dy2ty1 dy3ty1 dy4ty1 dy5ty1
    yycon2 yycon3 yycon4 yycon5
    dz1tz1 dz2tz1 dz3tz1 dz4tz1 dz5tz1
    zzcon2 zzcon3 zzcon4 zzcon5))

      (print-banner bmname args) 

;;;//---------------------------------------------------------------------
;;;//      Read input file (if it exists), else take
;;;//      defaults from parameters
;;;//---------------------------------------------------------------------
;      (get-input-pars)
      (printf "No input file inputbt.data, Using compiled defaults\n")
      (printf "Size: ~a X ~a X ~a\n" nx ny nz)
      (printf "Iterations: ~a dt: ~a\n" niter dt)
      (initialize u nx ny nz isize2 jsize2 ksize2 dnxm1 dnym1 dnzm1)
      (exact_rhs nx2 ny2 nz2 isize2 jsize2 ksize2 jsize3 forcing dnxm1 dnym1 dnzm1 ue buf cuf q
        rhs u c1 c2 0.25
        tx2 ty2 tz2
        xxcon1 xxcon2 xxcon3 xxcon4 xxcon5
        dx1tx1 dx2tx1 dx3tx1 dx4tx1 dx5tx1
        yycon1 yycon2 yycon3 yycon4 yycon5
        dy1ty1 dy2ty1 dy3ty1 dy4ty1 dy5ty1
        zzcon1 zzcon2 zzcon3 zzcon4 zzcon5
        dz1tz1 dz2tz1 dz3tz1 dz4tz1 dz5tz1)

      (CGspawn (if serial 0 num-threads) bt-body
        u us vs ws rho_i square qs rhs forcing lhs fjac njac
        nx ny nz 
        nx2 ny2 nz2 
        jsize1 ksize1 
        isize2 jsize2 ksize2 
        isize4 jsize4 ksize4 
        isize jsize ksize
        dnxm1 dnym1 dnzm1
        c1 c2 c1c2 c3c4 c1345 con43 dt dssp niter
        dx1tx1 dx2tx1 dx3tx1 dx4tx1 dx5tx1
        xxcon2 xxcon3 xxcon4 xxcon5
        dy1ty1 dy2ty1 dy3ty1 dy4ty1 dy5ty1
        yycon2 yycon3 yycon4 yycon5
        dz1tz1 dz2tz1 dz3tz1 dz4tz1 dz5tz1
        zzcon2 zzcon3 zzcon4 zzcon5
        tx1 tx2 dtdx1tx1 dtdx2tx1 dtdx3tx1 dtdx4tx1 dtdx5tx1
        ty1 ty2 dtdy1ty1 dtdy2ty1 dtdy3ty1 dtdy4ty1 dtdy5ty1
        tz1 tz2 dtdz1tz1 dtdz2tz1 dtdz3tz1 dtdz4tz1 dtdz5tz1)

      (let* ([verified (verify CLASS niter dt compute_rhs_thunk
        nx2 ny2 nz2 isize2 jsize2 ksize2 u rhs dnzm1 dnym1 dnxm1)])
        (print-verification-status CLASS verified bmname)
        (let* ([time (/ (read-timer 1) 1000)]
               [results (new-BMResults bmname CLASS nx ny nz niter time 
                                       (get-mflops time niter nx ny nz) 
                                       "floating point" 
                                       (if verified 1 0)
                                       serial 
                                       num-threads 
                                       -1)]) 
            (print-results results)))))))

(define (bt-body cg  u us vs ws rho_i square qs rhs forcing lhs_ fjac_ njac_
      nx ny nz 
      nx2 ny2 nz2 
      jsize1 ksize1 
      isize2 jsize2 ksize2 
      isize4 jsize4 ksize4 
      isize jsize ksize
      dnxm1 dnym1 dnzm1
      c1 c2 c1c2 c3c4 c1345 con43 dt dssp niter
      dx1tx1 dx2tx1 dx3tx1 dx4tx1 dx5tx1
      xxcon2 xxcon3 xxcon4 xxcon5
      dy1ty1 dy2ty1 dy3ty1 dy4ty1 dy5ty1
      yycon2 yycon3 yycon4 yycon5
      dz1tz1 dz2tz1 dz3tz1 dz4tz1 dz5tz1
      zzcon2 zzcon3 zzcon4 zzcon5
      tx1 tx2 dtdx1tx1 dtdx2tx1 dtdx3tx1 dtdx4tx1 dtdx5tx1
      ty1 ty2 dtdy1ty1 dtdy2ty1 dtdy3ty1 dtdy4ty1 dtdy5ty1
      tz1 tz2 dtdz1tz1 dtdz2tz1 dtdz3tz1 dtdz4tz1 dtdz5tz1
)
   (define s3 (* ksize4 (add1 nx)))
   (define s4 (* jsize4 (add1 nx)))
   (define lhs     (make-flvector s3 0.0))
   (define fjac    (make-flvector s4 0.0))
   (define njac    (make-flvector s4 0.0))
   (define (adi)
    (compute_rhs cg isize2 jsize2 ksize2 jsize1 ksize1 u us vs ws rho_i square qs 
      c1c2 rhs forcing nx2 ny2 nz2 c1 c2 dssp
      tx2 ty2 tz2 con43 dt
      dx1tx1 dx2tx1 dx3tx1 dx4tx1 dx5tx1
      xxcon2 xxcon3 xxcon4 xxcon5
      dy1ty1 dy2ty1 dy3ty1 dy4ty1 dy5ty1
      yycon2 yycon3 yycon4 yycon5
      dz1tz1 dz2tz1 dz3tz1 dz4tz1 dz5tz1
      zzcon2 zzcon3 zzcon4 zzcon5
    )
    
    (CG-B cg)
  
    (x_solve cg nz2 ny2 nx2
      jsize1 ksize1 
      isize2 jsize2 ksize2 
      isize4 jsize4 ksize4 
      isize jsize ksize isize
      u square rhs lhs fjac njac rho_i qs 
      c1 c2 c3c4 c1345 con43 dt 
      tx1 tx2 dtdx1tx1 dtdx2tx1 dtdx3tx1 dtdx4tx1 dtdx5tx1)

    (CG-B cg)

    (y_solve cg nz2 nx2 ny2
      jsize1 ksize1 
      isize2 jsize2 ksize2 
      isize4 jsize4 ksize4 
      isize jsize ksize jsize
      u square rhs lhs fjac njac rho_i qs 
      c1 c2 c3c4 c1345 con43 dt 
      ty1 ty2 dtdy1ty1 dtdy2ty1 dtdy3ty1 dtdy4ty1 dtdy5ty1)

    (CG-B cg)

    (z_solve cg ny2 nx2 nz2
      jsize1 ksize1 
      isize2 jsize2 ksize2 
      isize4 jsize4 ksize4 
      isize jsize ksize ksize
      u square rhs lhs fjac njac rho_i qs 
      c1 c2 c3c4 c1345 con43 dt 
      tz1 tz2 dtdz1tz1 dtdz2tz1 dtdz3tz1 dtdz4tz1 dtdz5tz1)

    (CG-B cg)

    (add cg nz2 ny2 nx2 jsize1 ksize1 isize2 jsize2 ksize2 u rhs)
    )

;;;//---------------------------------------------------------------------
;;;//      do one time step to touch all code, and reinitialize
;;;//---------------------------------------------------------------------
      (adi)

      (CG-n0-only cg
        (initialize u nx ny nz isize2 jsize2 ksize2 dnxm1 dnym1 dnzm1)

        (timer-start 1))

      (for ([step (in-range 1 (add1 niter))])
        (CG-n0-only cg
          (when (or (zero? (modulo step 20)) (= step 1) (= step niter))
            (printf "Time step ~a\n" step)))
        (adi))

      (CG-n0-only cg
        (timer-stop 1))

)

(define (get-mflops total-time niter nx ny nz)
  (if (not (= total-time 0.0))
    (let* ([n3 (* nx ny nz)]
           [t  (/ (+ nx ny nz) 3.0)])
      (/ (* (+ (* 3478.8 n3)
               (* -17655.7(* t t))
               (* 28023.7 t))
            niter)
          (* total-time 1000000.0)))
      0.0))

(define (exact_solution xi eta zeta dtemp offset)
  (for ([m (in-range 5)])
    (f! dtemp (+ m offset) 
      (+ (fr ce m)
         (* xi (+ (fr ce (+ m 5))
                  (* xi (+ (fr ce (+ m (* 4 5)))
                           (* xi (+ (fr ce (+ m (* 7 5)))
                                    (* xi (fr ce (+ m (* 10 5))))))))))
         (* eta (+ (fr ce (+ m (* 2 5)))
                  (* eta (+ (fr ce (+ m (* 5 5)))
                           (* eta (+ (fr ce (+ m (* 8 5)))
                                    (* eta (fr ce (+ m (* 11 5))))))))))
         (* zeta (+ (fr ce (+ m (* 3 5)))
                  (* zeta (+ (fr ce (+ m (* 6 5)))
                           (* zeta (+ (fr ce (+ m (* 9 5)))
                                    (* zeta (fr ce (+ m (* 12 5))))))))))))))
  
(define (initialize u nx ny nz isize1 jsize1 ksize1 dnxm1 dnym1 dnzm1)
  (for* ([k (in-range nz)]
         [j (in-range ny)]
         [i (in-range nx)]
         [m (in-range 5)])
    (let ([midx (+ m (* i isize1) (* j jsize1) (* k ksize1))])
      (f! u midx 1.0)))

  (let ([Pface (make-flvector (* 5 3 2) 0.0)])
    (for ([k (in-range nz)])
      (let ([zeta (* k dnzm1)])
        (for ([j (in-range ny)])
          (let ([eta (* j dnym1)])
            (for ([i (in-range nx)])
              (let ([xi (* i dnxm1)])
                (for ([ix (in-range 2)])
                  (exact_solution ix eta zeta Pface (+ 0 (* 0 5) (* ix 15))))
                (for ([ix (in-range 2)])
                  (exact_solution xi ix zeta Pface (+ 0 (* 1 5) (* ix 15))))
                (for ([ix (in-range 2)])
                  (exact_solution xi eta ix Pface (+ 0 (* 2 5) (* ix 15))))

                (for ([m (in-range 5)])
                  (let ([idx (+ m (* i isize1) (* j jsize1) (* k ksize1))]
                        [pxi   (+ (* xi           (fr Pface (+ m (* 0 5) (* 1 15))))
                                  (* (- 1.0 xi)   (fr Pface (+ m (* 0 5) (* 0 15)))))]
                        [peta  (+ (* eta          (fr Pface (+ m (* 1 5) (* 1 15))))
                                  (* (- 1.0 eta)  (fr Pface (+ m (* 1 5) (* 0 15)))))]
                        [pzeta (+ (* zeta         (fr Pface (+ m (* 2 5) (* 1 15))))
                                  (* (- 1.0 zeta) (fr Pface (+ m (* 2 5) (* 0 15)))))])
                    (f! u idx  (+ (- (+ pxi peta pzeta) 
                                        (* pxi peta) 
                                        (* pxi pzeta)
                                        (* peta pzeta))
                                     (* pxi peta pzeta))))))))))))
  (let ([temp (make-flvector 5 0.0)]
        [temp2 (make-flvector 5 0.0)]
        [i2 (sub1 nx)]
        [j2 (sub1 ny)]
        [k2 (sub1 nz)])
    (for ([k (in-range nz)])
      (let ([zeta (* k dnzm1)])
        (for ([j (in-range ny)])
          (let ([eta (* j dnym1)])
            (exact_solution 0.0 eta zeta temp 0)
            (exact_solution 1.0 eta zeta temp2 0)
            (for ([m (in-range 5)])
              (let* ([idx (+ m (* j jsize1) (* k ksize1))]
                     [idx2 (+ (* i2 isize1) idx)])
                (f! u idx  (fr temp m))      ;west face
                (f! u idx2 (fr temp2 m)))))) ;east face
            
        (for ([i (in-range nx)])
          (let ([xi (* i dnxm1)])
            (exact_solution xi 0.0 zeta temp 0)
            (exact_solution xi 1.0 zeta temp2 0)
            (for ([m (in-range 5)])
              (let* ([idx (+ m (* i isize1) (* k ksize1))]
                     [idx2 (+ (* j2 jsize1) idx)])
                (f! u idx  (fr temp m))        ;south face
                (f! u idx2 (fr temp2 m)))))))) ;north face
  
    (for ([j (in-range ny)])
      (let ([eta (* j dnym1)])
        (for ([i (in-range nx)])
          (let ([xi (* i dnxm1)])
            (exact_solution xi eta 0.0 temp 0)
            (exact_solution xi eta 1.0 temp2 0)
            (for ([m (in-range 5)])
              (let* ([idx (+ m (* i isize1) (* j jsize1))]
                     [idx2 (+ (* k2 ksize1) idx)])
                (f! u idx  (fr temp m))          ;bottom face
                (f! u idx2 (fr temp2 m)))))))))) ;top face

(define (lhsinit lhs size isize4 jsize4 ksize4)
  (let* ([js42 (fx+ jsize4 jsize4)])
    (define-syntax-rule (DOIT IK)
      (let ([ik IK])
        (for ([m (in-range 5)])
          (let ([nis4 (fx* m isize4)])
            (for ([n (in-range 5)])
              (let ([idx (fx+ n (fx* m isize4) ik)])
                (f! lhs idx 0.0)
                (f! lhs (fx+ jsize4 idx) 0.0)
                (f! lhs (fx+ js42 idx) 0.0))))
          (f! lhs (fx+ m (fx* m isize4) jsize4 ik) 1.0))))
    (DOIT 0)
    (DOIT (fx* size ksize4))))

(define (add cg nz2 ny2 nx2 jsize1 ksize1 isize2 jsize2 ksize2 u rhs)
  (CGfor cg ([k (in-range 1 (fx++ nz2))])
    (define ki (fx* k ksize2))
    (for ([j (in-range 1 (fx++ ny2))])
    (define ji (fx+ ki (fx* j jsize2)))
    (for ([i (in-range 1 (fx++ nx2))])
    (define ii (fx+ ji (fx* i isize2)))
    (for ([m (in-range 5)])
    (let ([idx (fx+ m ii)])
      (f!+ u idx (fr rhs idx))))))))

(define-syntax-rule (matvec_sub ablock blkoffst avect avcoffst bvect bvcoffst)
  (for ([i (in-range 5)])
    (f!+ bvect (fx+ i bvcoffst)
      (for/fold ([S 0.0]) ([n (in-range 0 21 5)]
                           [j (in-range 5)])
        (fl- S (fl* (fr ablock (+ i n blkoffst)) (fr avect (+ j avcoffst))))))))

(define-syntax-rule (matmul_sub ablock ablkoffst bblock bblkoffst cblock cblkoffst)
  (for ([nj (in-range 0 21 5)])
    (for ([i (in-range 5)])
      (f! cblock (+ i nj cblkoffst)
        (for/fold ([S (fr cblock (+ i nj cblkoffst))]) ([m (in-range 0 21 5)]
                             [k (in-range 5)])
        (fl- S (fl* (fr ablock (+ i m ablkoffst)) (fr bblock (+ k nj bblkoffst)))))))))
 
(define (binvcrhs lhss lhsoffst c coffst r roffst)
  (define-syntax-rule (V- V I N C J O) (f!- V (fx+ I N O) (fl* C (fr V (fx+ J N O)))))
  (define-syntax-rule (lhss- I N C J)  (V- lhss I N C J lhsoffst))
  (define-syntax-rule (c-   I N C J)   (V- c I N C J coffst))
  (define-syntax-rule (r-   I C J)     (f!- r (fx+ I roffst) (fl* C (fr r (fx+ J roffst)))))
  (define-syntax-rule (lhss* I N C)    (f!* lhss (fx+ I N lhsoffst) C))
  (define-syntax-rule (c*   I N C)     (f!* c (fx+ I N coffst) C))
  (define-syntax-rule (r*   I C)       (f!* r (fx+ I roffst) C))

  (for ([P (in-range 5)]
        [nP (in-range 0 21 5)]
        [nP1 (in-range 5 26 5)])
    (let ([pivot (/ 1.0 (fr lhss (+ P nP lhsoffst)))])
        (for ([n (in-range nP1 21 5)]) (lhss* P n pivot))
        (for ([n (in-range 0   21 5)]) (c*    P n pivot))
        (r* P pivot))
    (for ([i (in-range 0  5)] #:when (not (= i P)))
      (let ([coeff (fr lhss (+ i nP lhsoffst))])
        (for ([n (in-range nP1 21 5)]) (lhss- i n coeff P))
        (for ([n (in-range 0   21 5)]) (c-    i n coeff P))
        (r- i coeff P)))))

(define (binvrhs lhss lhsoffst r roffst)
  (define-syntax-rule (V- V I N C J O) (f!- V (fx+ I N O) (fl* C (fr V (fx+ J N O)))))
  (define-syntax-rule (lhss- I N C J) (V- lhss I N C J lhsoffst))
  (define-syntax-rule (r-   I C J) (f!- r (fx+ I roffst) (fl* C (fr r (fx+ J roffst)))))
  (define-syntax-rule (lhss* I N C) (f!* lhss (fx+ I N lhsoffst) C))
  (define-syntax-rule (r*   I C)   (f!* r (fx+ I roffst) C))

  (for ([P (in-range 5)]
        [nP (in-range 0 21 5)]
        [nP1 (in-range 5 26 5)])
    (let ([pivot (/ 1.0 (fr lhss (+ P nP lhsoffst)))])
        (for ([n (in-range nP1 21 5)]) (lhss* P n pivot))
        (r* P pivot))
    (for ([i (in-range 0  5)] #:when (not (= i P)))
      (let ([coeff (fr lhss (+ i nP lhsoffst))])
        (for ([n (in-range nP1 21 5)]) (lhss- i n coeff P))
        (r- i coeff P)))))




(define (error-norm rms nx2 ny2 nz2 isize1 jsize1 ksize1 u dnzm1 dnym1 dnxm1)
  (for ([m (in-range 5)]) (f! rms m 0.0))

  (let ([u-exact (make-flvector 5 0.0)])
    (for ([k (in-range (+ nz2 2))])
      (let ([zeta (* k dnzm1)])
        (for ([j (in-range (+ ny2 2))])
          (let ([eta (* j dnym1)])
            (for ([i (in-range (+ nx2 2))])
              (let ([xi (* i dnxm1)])
                (exact_solution xi eta zeta u-exact 0)
                (for ([m (in-range 5)])
                  (let* ([idx (+ m (fx* i isize1) (fx* j jsize1) (fx* k ksize1))]
                         [add (fl- (fr u idx) (fr u-exact m))])
                    (f!+ rms m (flsqr add)))))))))))

  
  (for ([m (in-range 5)])
    (f! rms m (sqrt (/ (fr rms m) nx2 ny2 nz2)))))

(define (rhs-norm rms nz2 ny2 nx2 isize1 jsize1 ksize1 rhs)
  (for ([m (in-range 5)]) (f! rms m 0.0))

  (for* ([k (in-range 1 (add1 nz2))]
         [j (in-range 1 (add1 ny2))]
         [i (in-range 1 (add1 nx2))]
         [m (in-range 5)])
    (let* ([idx (fx+ m (fx* i isize1) (fx* j jsize1) (fx* k ksize1))]
           [add (fr rhs idx)])
      (f!+ rms m (flsqr add))))
  
  (for ([m (in-range 5)])
    (f! rms m (sqrt (/ (fr rms m) nx2 ny2 nz2)))))

(define-syntax-rule (fourth-order-dissipation ii nII2 V V2 m midx idx
  MIDX OFFSET 
  DIDX IDX dssp)

  (begin
  (let* ([ii 1]
         [idx IDX])
    (for ([m (in-range 5)])
      (let* ([midx   MIDX]
             [midx+  (fx+ midx OFFSET)]
             [midx+2 (fx+ midx+ OFFSET)]
             [didx   DIDX])
        (f!- V didx (fl* dssp (fl+ (fl*  5.0 (fr V2 midx))
                                   (fl* -4.0 (fr V2 midx+))
                                             (fr V2 midx+2)))))))
  (let* ([ii 2]
         [idx IDX])
    (for ([m (in-range 5)])
      (let* ([midx   MIDX]
             [midx+  (fx+ midx OFFSET)]
             [midx+2 (fx+ midx+ OFFSET)]
             [midx-  (fx- midx OFFSET)]
             [didx   DIDX])
        (f!- V didx (fl* dssp (fl+ (fl* -4.0 (fr V2 midx-)) 
                                   (fl*  6.0 (fr V2 midx))
                                   (fl* -4.0 (fr V2 midx+))
                                             (fr V2 midx+2)))))))
  (for ([ii (in-range 3 (sub1 nII2))])
    (let ([idx IDX])
      (for ([m (in-range 5)])
        (let* ([midx   MIDX]
               [midx+  (fx+ midx OFFSET)]
               [midx+2 (fx+ midx+ OFFSET)]
               [midx-  (fx- midx OFFSET)]
               [midx-2 (fx- midx- OFFSET)]
               [didx   DIDX])
          (f!- V didx (fl* dssp (fl+           (fr V2 midx-2)
                                     (fl* -4.0 (fr V2 midx-))
                                     (fl*  6.0 (fr V2 midx))
                                     (fl* -4.0 (fr V2 midx+))
                                               (fr V2 midx+2))))))))
  (let* ([ii (sub1 nII2)]
         [idx IDX])
    (for ([m (in-range 5)])
      (let* ([midx   MIDX]
             [midx+  (fx+ midx OFFSET)]
             [midx-  (fx- midx OFFSET)]
             [midx-2 (fx- midx- OFFSET)]
             [didx   DIDX])
        (f!- V didx (fl* dssp (fl+           (fr V2 midx-2)
                                   (fl* -4.0 (fr V2 midx-))
                                   (fl*  6.0 (fr V2 midx))
                                   (fl* -4.0 (fr V2 midx+))))))))
  (let* ([ii nII2]
         [idx IDX])
    (for ([m (in-range 5)])
      (let* ([midx   MIDX]
             [midx-  (fx- midx OFFSET)]
             [midx-2 (fx- midx- OFFSET)]
             [didx   DIDX])
        (f!- V didx (fl* dssp (fl+           (fr V2 midx-2)
                                   (fl* -4.0 (fr V2 midx-))
                                   (fl*  5.0 (fr V2 midx))))))))))

(define (exact_rhs nx2 ny2 nz2 isize1 jsize1 ksize1 jsize3 forcing dnxm1 dnym1 dnzm1 ue buf cuf q
  rhs u c1 c2 dssp
  tx2 ty2 tz2
  xxcon1 xxcon2 xxcon3 xxcon4 xxcon5
  dx1tx1 dx2tx1 dx3tx1 dx4tx1 dx5tx1
  yycon1 yycon2 yycon3 yycon4 yycon5
  dy1ty1 dy2ty1 dy3ty1 dy4ty1 dy5ty1
  zzcon1 zzcon2 zzcon3 zzcon4 zzcon5
  dz1tz1 dz2tz1 dz3tz1 dz4tz1 dz5tz1)

  (for* ([k (in-range (fx+ 2 nz2))]
         [j (in-range (fx+ 2 ny2))]
         [i (in-range (fx+ 2 nx2))]
         [m (in-range 5)])
    (let ([idx (fx+ m (fx* i isize1) (fx* j jsize1) (fx* k ksize1))])
      (f!+ forcing idx 0.0)))

(define-syntax-case (body2 A dtemp)
    (with-syntax-values ([(NII2 NJJ2 NKK2) (PICK3 #'A (nx2 ny2 nz2) (ny2 nx2 nz2) (nz2 nx2 ny2))]
                         [(ii jj kk) (PICK3 #'A (i j k) (j i k) (k i j))]
                         [(jjjjsize1 kkkksize1) (PICK3 #'A ((fx* j jsize1) (fx* k ksize1))
                                                           ((fx* i isize1) (fx* k ksize1))
                                                           ((fx* i isize1) (fx* j jsize1)))]
                         [(d_1t_1 d_2t_1 d_3t_1 d_4t_1 d_5t_1) (PICK3 #'A 
                                                                 (dx1tx1 dx2tx1 dx3tx1 dx4tx1 dx5tx1)
                                                                 (dy1ty1 dy2ty1 dy3ty1 dy4ty1 dy5ty1)
                                                                 (dz1tz1 dz2tz1 dz3tz1 dz4tz1 dz5tz1))]
                         [(_con_0 _con_1 _con_2 __con3 __con4 __con5) (PICK3 #'A
                                                                 (xxcon1 xxcon2 xxcon2 xxcon3 xxcon4 xxcon5)
                                                                 (yycon2 yycon1 yycon2 yycon3 yycon4 yycon5)
                                                                 (zzcon2 zzcon2 zzcon1 zzcon3 zzcon4 zzcon5))]
                         [(t_2 t_2m1 t_2m2 t_2m3) (PICK3 #'A
                                                     (tx2 KIDENT KZERO KZERO)
                                                     (ty2 KZERO KIDENT KZERO)
                                                     (tz2 KZERO KZERO KIDENT))]
                         [(zs iisize1 f1jsize3) (PICK3 #'A (us isize1 jsize3) (vs jsize1 (fx* 2 jsize3)) (ws ksize1 (fx* 3 jsize3)))])
  #'(begin
    (for ([kk (in-range 1 (add1 NKK2))])
      (for ([jj (in-range 1 (add1 NJJ2))])
        (let* ([JKIDX2 (fx+ jjjjsize1 kkkksize1)])
          (for ([ii (in-range 0 (+ NII2 2))])
              (let ([xi (* i dnxm1)]
                    [eta (* j dnym1)]
                    [zeta (* k dnzm1)])
                (exact_solution xi eta zeta dtemp 0)
                (let ([dtpp (/ 1.0 (fr dtemp 0))])
                  (for ([m (in-range 5)])
                    (let ([idx (+ ii (* m jsize3))]
                          [dtv (fr dtemp m)])
                    (f! ue idx dtv)
                    (f! buf idx (* dtpp dtv)))))
                (let* ([i1j  (+ ii (* 1 jsize3))]
                       [i2j (+ ii (* 2 jsize3))]
                       [i3j (+ ii (* 3 jsize3))]
                       [bufij (fr buf i1j)]
                       [bufi2j (fr buf i2j)]
                       [bufi3j (fr buf i3j)]
                       [ueij (fr ue i1j)]
                       [uei2j (fr ue i2j)]
                       [uei3j (fr ue i3j)]
                       [bufij2 (flsqr bufij)]
                       [bufi2j2 (flsqr bufi2j)]
                       [bufi3j2 (flsqr bufi3j)])
                (f! cuf ii (flsqr (fr buf (+ ii (* A jsize3)))))
                (f! buf ii (+ bufij2 bufi2j2 bufi3j2))
                (f! q ii (* 0.5 (+ (* bufij ueij) (* bufi2j uei2j) (* bufi3j uei3j)))))))

          (for ([ii (in-range 1 (add1 NII2))])
            (let* ([ip1 (add1 ii)]
                   [im1 (sub1 ii)]
                   [didx (+ (* i isize1) (* j jsize1) (* k ksize1))]
                   [idx2 (+ ii f1jsize3)]
                   [idx2+ (+ ip1 f1jsize3)]
                   [idx2- (+ im1 f1jsize3)]
                   [A4J (+ ii (* 4 jsize3))]
                   [A4J+ (+ A4J 1)]
                   [A4J- (- A4J 1)])

              (define-syntax-rule (citA C C1 C2 C3) (fl* C (+ (- C1 (* 2.0 C2)) C3)))
              (define-syntax-rule (citS3 C V I1 I2 I3) (citA C (fr V I1) (fr V I2) (fr V I3)))
              (define-syntax-rule (citS C V) (citA C (fr V ip1) (fr V ii) (fr V im1)))

              (define-syntax-rule (t_2it l r) (- (fl* t_2 (fl- l r))))
              (define-syntax-rule (t_2it3 l r o) (- (fl* t_2 (+ (fl- l r) o))))
              (define-syntax-rule (t_2itlr UI ZSI) (* (fr ue UI) (fr buf ZSI)))
              (define-syntax-rule (t_2ito) (- (fl* c2 (fl- (fr ue A4J+) (fr q ip1)))
                                              (fl* c2 (fl- (fr ue A4J-) (fr q im1)))))

              (define-syntax-rule (mid d__t_1 __con2X AA t_2itother)
                   (let* ([AJ (fx+ ii (fx* AA jsize3))]
                          [AJ+ (fx+ AJ 1)]
                          [AJ- (fx- AJ 1)])
                (f!+ forcing (+ didx AA)
                  (citS3 d__t_1 ue AJ+ AJ AJ-)
                  (citS3 __con2X buf AJ+ AJ AJ-)
                  (t_2it3 (t_2itlr AJ+ idx2+)
                         (t_2itlr AJ- idx2-)
                         (t_2itother (t_2ito))))))

              (f!+ forcing didx 
                   (t_2it (fr ue idx2+)
                          (fr ue idx2-))
                   (citS d_1t_1 ue))

              (mid d_2t_1 _con_0 1 t_2m1)
              (mid d_3t_1 _con_1 2 t_2m2)
              (mid d_4t_1 _con_2 3 t_2m3)

              (define-syntax-rule (t4clause I1 I2 I3)
                (* (fr buf I1) (- (* c1 (fr ue I2)) (* c2 (fr q I3)))))
              (f!+ forcing (+ didx 4)
                   (t_2it (t4clause idx2+ A4J+ ip1) (t4clause idx2- A4J- im1))
                   (* 0.5 (citS __con3 buf))
                   (citS __con4 cuf)
                   (citS3 __con5 buf A4J+ A4J A4J-)
                   (citS3 d_5t_1 ue A4J+ A4J A4J-))))

;//---------------------------------------------------------------------
;//            Fourth-order dissipation
;//---------------------------------------------------------------------
    (fourth-order-dissipation ii NII2 forcing ue m midx idx
              (fx+ ii (fx* m jsize3)) 
              1
              (fx+ m idx) 
              (fx+ JKIDX2 (fx* ii iisize1)) dssp)
))))))

  (define-syntax-rule (KZERO a ...) 0.0)
  (define-syntax-rule (KIDENT a ...) (begin a ...))

  (let ([dtemp (make-flvector 5 0.0)])
    (body2 1 dtemp)
    (body2 2 dtemp)
    (body2 3 dtemp))

  (for* ([k (in-range 1 (add1 nz2))]
         [j (in-range 1 (add1 ny2))]
         [i (in-range 1 (add1 nx2))]
         [m (in-range 5)])
    (f!* forcing (fx+ m (fx* i isize1) (fx* j jsize1) (fx* k ksize1)) -1.0))
)

(define (compute_rhs cg isize2 jsize2 ksize2 jsize1 ksize1 u us vs ws rho_i square qs 
c1c2 rhs forcing nx2 ny2 nz2 c1 c2 dssp
    tx2 ty2 tz2 con43 dt
    dx1tx1 dx2tx1 dx3tx1 dx4tx1 dx5tx1
    xxcon2 xxcon3 xxcon4 xxcon5
   dy1ty1 dy2ty1 dy3ty1 dy4ty1 dy5ty1
    yycon2 yycon3 yycon4 yycon5
    dz1tz1 dz2tz1 dz3tz1 dz4tz1 dz5tz1
    zzcon2 zzcon3 zzcon4 zzcon5
)
  (CGfor cg ([k (in-range 0 (fx+ nz2 2))])
    (for* ([j (in-range (fx+ ny2 2))]
           [i (in-range (fx+ nx2 2))])
    (let* ([idx (fx+ (fx* i isize2) (fx* j jsize2) (fx* k ksize2))]
           [idx2 (fx+ i (fx* j jsize1) (fx* k ksize1))]
           [rho_inv (fl/ 1.0 (fr u idx))]
           [u1 (fr u (fx+ idx 1))]
           [u2 (fr u (fx+ idx 2))]
           [u3 (fr u (fx+ idx 3))]
           [u4 (fr u (fx+ idx 4))]
           [sq (fl* 0.5 (fl+ (flsqr u1) (flsqr u2) (flsqr u3)) rho_inv)])
      (f! rho_i idx2 rho_inv)
      (f! us idx2 (fl* rho_inv u1))
      (f! vs idx2 (fl* rho_inv u2))
      (f! ws idx2 (fl* rho_inv u3))
      (f! square idx2 sq)
      (f! qs idx2 (fl* rho_inv sq))

      (for* ([m (in-range 5)])
        (let ([midx (fx+ m idx)])
        (f! rhs midx (fr forcing midx)))))))

  (CG-B cg)

  (define-syntax-rule (KZERO a ...) 0.0)
  (define-syntax-rule (KIDENT a ...) (begin a ...))

  (define-syntax-case (DISSIP A)
    (with-syntax-values ([(nkk2 njj2 nii2) (PICK3 #'A (nz2 ny2 nx2) (nz2 nx2 ny2) (nx2 ny2 nz2))]
                         [(kk jj ii) (PICK3 #'A (k j i) (k i j) (i j k))]
                         [(kksize2 jjsize2 iisize2) (PICK3 #'A (ksize2 jsize2 isize2)
                                                               (ksize2 isize2 jsize2)
                                                               (isize2 jsize2 ksize2))]
                         [(iiiisize1 jjjjsize1 kkkksize1) (PICK3 #'A (i (fx* j jsize1) (fx* k ksize1))
                                                                     ((fx* j jsize1) i (fx* k ksize1))
                                                                     ((fx* k ksize1) (fx* j jsize1) i))]
                         [(d_1t_1 d_2t_1 d_3t_1 d_4t_1 d_5t_1) (PICK3 #'A 
                                                                 (dx1tx1 dx2tx1 dx3tx1 dx4tx1 dx5tx1)
                                                                 (dy1ty1 dy2ty1 dy3ty1 dy4ty1 dy5ty1)
                                                                 (dz1tz1 dz2tz1 dz3tz1 dz4tz1 dz5tz1))]
                         [(_con_0 _con_1 _con_2 __con3 __con4 __con5) (PICK3 #'A
                                                                 ((fl* xxcon2 con43) xxcon2 xxcon2 xxcon3 xxcon4 xxcon5)
                                                                 (yycon2 (fl* yycon2 con43) yycon2 yycon3 yycon4 yycon5)
                                                                 (zzcon2 zzcon2 (fl* zzcon2 con43) zzcon3 zzcon4 zzcon5))]
                         [(t_2 t_2m1 t_2m2 t_2m3) (PICK3 #'A
                                                     (tx2 KIDENT KZERO KZERO)
                                                     (ty2 KZERO KIDENT KZERO)
                                                     (tz2 KZERO KZERO KIDENT))]
                         [(zs iisize1) (PICK3 #'A (us 1) (vs jsize1) (ws ksize1))])

    #'(CGfor cg ([kk (in-range 1 (fx++ nkk2))])
      (for ([jj (in-range 1 (fx++ njj2))])
        (let* ([JKIDX  (fx+ (fx* jj jjsize2) (fx* kk kksize2))]
               [JKIDX2 (fx+ jjjjsize1 kkkksize1)])
        (for ([ii (in-range 1 (fx++ nii2))])
          (let* ([idx    (fx+ (fx* ii iisize2) JKIDX)]
                 [idx2   (fx+ iiiisize1 JKIDX2)]
                 [idx4   (fx+ idx 4)]
                 [idxz+  (fx+ idx iisize2)]
                 [idxz-  (fx- idx iisize2)]
                 [idxz+4 (fx+ idxz+ 4)]
                 [idxz-4 (fx+ idxz- 4)]
                 [idxz+2 (fx+ idxz+ iisize2)]
                 [idxz-2 (fx- idxz-  iisize2)]
                 [idx2z+ (fx+ idx2 iisize1)]
                 [idx2z- (fx- idx2 iisize1)])

            (define-syntax-rule (citA C C1 C2 C3) (fl* C (fl+ (fl- C1 (fl* 2.0 C2)) C3)))
            (define-syntax-rule (cit3S C V I1 I2 I3) (citA C (fr V I1) (fr V I2) (fr V I3)))
            (define-syntax-rule (cit2 C V)  (citA C (fr V idx2z+) (fr V idx2) (fr V idx2z-)))
            (define-syntax-rule (cit3 C F V)(citA C (F (fr V idx2z+)) (F (fr V idx2)) (F (fr V idx2z-))))
            (define-syntax-rule (t_2m)
              (fl* (fl- (fl+ (fr u idxz+4) (fr square idx2z-))
                        (fl+ (fr square idx2z+) (fr u idxz-4))) 
                   c2))
            (define-syntax-rule (t_2it l r) (fl- (fl* t_2 (fl- l r))))
            (define-syntax-rule (t_2it3 l r o) (fl- (fl* t_2 (fl+ (fl- l r) o))))
            (define-syntax-rule (t_2itlr UI ZSI) (fl* (fr u UI) (fr zs ZSI)))

            (define-syntax-rule (mid d__t_1 __con2X ZS AA t_2m_)
              (let ([idxA   (fx+ idx   AA)]
                    [idxz+A (fx+ idxz+ AA)]
                    [idxz-A (fx+ idxz- AA)])
                (f!+ rhs idxA
                  (cit3S d__t_1 u idxz+A idxA idxz-A)
                  (cit2 __con2X ZS)
                  (t_2it3 (t_2itlr idxz+A idx2z+)
                          (t_2itlr idxz-A idx2z-)
                           (t_2m_ (t_2m))))))
        
            (f!+ rhs idx
              (cit3S d_1t_1 u idxz+ idx idxz-)
              (t_2it (fr u (fx+ idxz+ A)) 
                     (fr u (fx+ idxz- A))))

            (mid d_2t_1 _con_0 us 1 t_2m1)
            (mid d_3t_1 _con_1 vs 2 t_2m2)
            (mid d_4t_1 _con_2 ws 3 t_2m3)

            (define-syntax-rule (CONS5W UI RI) (fl* (fr u UI) (fr rho_i RI)))
            (define-syntax-rule (T_25W UI RI) (fl* (fl- (fl* c1 (fr u UI))
                                                        (fl* c2 (fr square RI)))
                                                   (fr zs RI)))
            (f!+ rhs idx4 
              (cit3S d_5t_1 u idxz+4 idx4 idxz-4)
              (cit2 __con3 qs)
              (cit3 __con4 flsqr zs)
              (citA __con5 (CONS5W idxz+4 idx2z+)
                           (CONS5W idx4 idx2)
                           (CONS5W idxz-4 idx2z-))
              (t_2it (T_25W idxz+4 idx2z+)
                     (T_25W idxz-4 idx2z-)))))

        (fourth-order-dissipation ii nii2 rhs u m midx idx 
        (fx+ m JKIDX (fx* ii iisize2)) 
        iisize2
        midx 
        (fx+ JKIDX (fx* ii iisize2)) 
        dssp))))))

  (DISSIP 1)

  (CG-B cg)

  (DISSIP 2)

  (CG-B cg)

  (DISSIP 3)

  (CG-B cg)

  (CGfor cg ([k (in-range 1 (fx++ nz2))])
    (define ki (fx* k ksize2))
    (for ([j (in-range 1 (fx++ ny2))])
    (define ji (fx+ ki (fx* j jsize2)))
    (for ([i (in-range 1 (fx++ nx2))])
    (define ii (fx+ ji (fx* i isize2)))
    (for ([m (in-range 5)])
    (let ([idx (fx+ m ii)])
      (f!* rhs idx dt)))))))

(define (verify class no_time_steps dt compute_rhs_thunk
  nx2 ny2 nz2 isize1 jsize1 ksize1 u rhs dnzm1 dnym1 dnxm1)
  (define xcrdif (make-flvector 5 0.0))
  (define xcedif (make-flvector 5 0.0))
  (define xcr (make-flvector 5 0.0))
  (define xce (make-flvector 5 0.0))
  (define-values (xcrref xceref dtref) (get-verify-values class))

;;;//---------------------------------------------------------------------
;;;//   compute the error norm and the residual norm, and exit if not printing
;;;//---------------------------------------------------------------------
    (error-norm xce nx2 ny2 nz2 isize1 jsize1 ksize1 u dnzm1 dnym1 dnxm1)
    (compute_rhs_thunk)
    (rhs-norm xcr nz2 ny2 nx2 isize1 jsize1 ksize1 rhs)

    (for ([m (in-range 5)]) 
      (f!/ xcr m dt))

;;;//---------------------------------------------------------------------
;;;//    reference data for 12X12X12 grids after 100 time steps, with DT = 1.50d-02
;;;//---------------------------------------------------------------------
;;;//---------------------------------------------------------------------
;;;//    Reference values of RMS-norms of residual.
;;;//---------------------------------------------------------------------
;;;//---------------------------------------------------------------------
;;;//    Reference values of RMS-norms of solution error.
;;;//---------------------------------------------------------------------

    (for ([m (in-range 5)]) 
      (let ([xcrr (fr xcrref m)]
            [xcer (fr xceref m)])
        (f! xcrdif m (abs (/ (- (fr xcr m) xcrr) xcrr)))
        (f! xcedif m (abs (/ (- (fr xce m) xcer) xcer)))))

  (define  epsilon 1.0E-8)
  (begin0
    (if (not (equal? class #\U))
      (let ([verified (and ((abs (- dt dtref)) . <= . epsilon)
                           (<epsilon-vmap xcrdif epsilon)
                           (<epsilon-vmap xcedif epsilon))])
        (printf "Verification being performed for class ~a\n" class)
        (printf "Accuracy setting for epsilon = ~a\n" epsilon)
        (unless verified (printf "DT does not match the reference value of ~a\n" dtref))
        verified)
      (begin
        (printf " Unknown CLASS")
        (printf " RMS-norms of residual")
        -1))
    (printf "Comparison of RMS-norms of residual\n")
    (for ([m (in-range (flvector-length xcr))])
      (printf "~a. ~a ~a ~a\n" m (fr xcr m) (fr xcrref m) (fr xcrdif m)))
    (printf "Comparison of RMS-norms of solution error\n")
    (for ([m (in-range (flvector-length xce))])
      (printf "~a. ~a ~a ~a\n" m (fr xce m) (fr xceref m) (fr xcedif m)))))

(define-syntax-case (__solve NAME R)
  (with-syntax-values ([(kk jj ii nkk2 njj2 nii2 kksize2 jjsize2 iisize2) 
    (PICK3 #'R (k j i nz ny nx ksize2 jsize2 isize2) 
               (k i j nz nx ny ksize2 isize2 jsize2) 
               (j i k ny nx nz jsize2 isize2 ksize2))])

#'(define (NAME cg nkk2 njj2 nii2 jsize1 ksize1 isize2 jsize2 ksize2 isize4 jsize4 ksize4 isize jsize ksize IISIZE u square rhs lhs fjac njac rho_i qs c1 c2 c3c4 c1345 con43 dt t_1 t_2 dtd_1t_1 dtd_2t_1 dtd_3t_1 dtd_4t_1 dtd_5t_1)
  
  (CGfor cg ([kk (in-range 1 (fx++ nkk2))])
    (for ([jj (in-range 1 (fx++ njj2))])
      (define kkjjsize2 (fx+ (fx* jj jjsize2) (fx* kk kksize2)))
      (for ([ii (in-range (fx+ nii2 2))])
        (let* ([i0jk4 (fx* ii jsize4)]
               [i1jk4  (fx+ (fx* 1 isize4) i0jk4)]
               [i2jk4  (fx+ (fx* 2 isize4) i0jk4)]
               [i3jk4  (fx+ (fx* 3 isize4) i0jk4)]
               [i4jk4  (fx+ (fx* 4 isize4) i0jk4)]
               [ijk1   (fx+ i (fx* j jsize1) (fx* k ksize1))]
               [ijk2   (fx+ (fx* ii iisize2) kkjjsize2)]
               [ijk21  (fx+ 1 ijk2)]
               [ijk22  (fx+ 2 ijk2)]
               [ijk23  (fx+ 3 ijk2)]
               [ijk24  (fx+ 4 ijk2)]
               [tmp1 (fr rho_i ijk1)]
               [tmp2 (flsqr tmp1)]
               [tmp3 (fl* tmp1 tmp2)])

          (define-syntax-case (DIAG0 V A V1 V2 V3 V4 V5)
            #'(begin
                (f! V (fx+ A i0jk4) V1)
                (f! V (fx+ A i1jk4) V2)
                (f! V (fx+ A i2jk4) V3)
                (f! V (fx+ A i3jk4) V4)
                (f! V (fx+ A i4jk4) V5)))

          (define-syntax-case (ROTASN V A R1 V1 V2 V3 V4 V5)
            (with-syntax ([(NS (... ...)) (PICK3 #'R1 (V2 V3 V4) (V3 V2 V4) (V4 V3 V2))])
              #'(DIAG0 V A V1 NS (... ...) V5)))

          (ROTASN fjac 0 R 0.0 1.0 0.0 0.0 0.0)

           (let-syntax-with-values ([(A1 A2 A3) (PICK3 #'R (1 2 3) (2 1 3) (3 2 1))]) 
            #'(let* ([u0 (fr u ijk2)]
                     [uA1 (fr u (fx+ A1 ijk2))]
                     [uA2 (fr u (fx+ A2 ijk2))]
                     [uA3 (fr u (fx+ A3 ijk2))]
                     [u4 (fr u (fx+ 4 ijk2))]
                     [uR (fr u (fx+ R ijk2))]
                     [tmp2sqruA1 (fl* tmp2 (flsqr uA1))]
                     [tmp1uA2 (fl* tmp1 uA2)]
                     [tmp1uA3 (fl* tmp1 uA3)]
                     [tmp1uR (fl* tmp1 uR)]
                     [tmp2uA2uR (fl* tmp2 uA2 uR)]
                     [tmp2uA3uR (fl* tmp2 uA3 uR)])
                
              (ROTASN fjac A1 R
                (fl- (fl* c2 (fr qs ijk1)) tmp2sqruA1)
                (fl/ (fl* (fl- 2.0 c2) uA1) u0)
                (fl- (fl* c2 tmp1uA2))
                (fl- (fl* c2 tmp1uA3))
                c2)
              (ROTASN fjac A2 R
                (fl- tmp2uA2uR)
                 tmp1uA2
                tmp1uR
                0.0
                0.0)
              (ROTASN fjac A3 R
                (fl- tmp2uA3uR)
                tmp1uA3
                0.0
                tmp1uR
                0.0)
              (ROTASN fjac 4 R
                (fl* tmp2 uR (fl- (fl* c2 2.0 (fr square ijk1))
                                  (fl* c1 u4)))
                (fl- (fl* c1 tmp1 u4)
                     (fl* c2 tmp2sqruA1)
                     (fl* c2 (fr qs ijk1)))
                (fl- (fl* c2 tmp2uA2uR))
                (fl- (fl* c2 tmp2uA3uR))
                (fl* c1 tmp1uR))
                ))

          (define-syntax-case (R43IT A a (... ...))
            (let ([aa (syntax->datum #'A)] 
                  [rr (syntax->datum #'R)])
              (if (= aa rr) 
                #'(fl* con43 a (... ...))
                #'(fl* a (... ...)))))
                
           
          (define-syntax-case (NJACM A)
            #'
            (ROTASN njac A A
              (fl- (R43IT A c3c4 tmp2 (fr u (fx+ A ijk2))))
              (R43IT A c3c4 tmp1)
              0.0
              0.0
              0.0))


          (DIAG0 njac 0 0.0 0.0 0.0 0.0 0.0)
          (NJACM 1)
          (NJACM 2)
          (NJACM 3)
          (DIAG0 njac 4
            (fl- 0.0 
               (fl* (fl- (R43IT 1 c3c4) c1345) tmp3 (flsqr (fr u ijk21)))
               (fl* (fl- (R43IT 2 c3c4) c1345) tmp3 (flsqr (fr u ijk22)))
               (fl* (fl- (R43IT 3 c3c4) c1345) tmp3 (flsqr (fr u ijk23)))
               (fl* c1345 tmp2 (fr u ijk24)))
            (fl* (fl- (R43IT 1 c3c4) c1345) tmp2 (fr u ijk21))
            (fl* (fl- (R43IT 2 c3c4) c1345) tmp2 (fr u ijk22))
            (fl* (fl- (R43IT 3 c3c4) c1345) tmp2 (fr u ijk23))
            (fl* c1345 tmp1))))
      
      (lhsinit lhs IISIZE isize4 jsize4 ksize4)
      
      (let ([tmp1 (fl* dt t_1)]
            [tmp2 (fl* dt t_2)]
            [dtd_1t_1*2+1 (fl+ 1.0 (fl* dtd_1t_1 2.0))]
            [dtd_2t_1*2+1 (fl+ 1.0 (fl* dtd_2t_1 2.0))]
            [dtd_3t_1*2+1 (fl+ 1.0 (fl* dtd_3t_1 2.0))]
            [dtd_4t_1*2+1 (fl+ 1.0 (fl* dtd_4t_1 2.0))]
            [dtd_5t_1*2+1 (fl+ 1.0 (fl* dtd_5t_1 2.0))])
      (for ([ii (in-range 1 IISIZE)])
        (let ([di (fx+ (fx* 0 jsize4) (fx* ii ksize4))]
              [si- (fx* (fx-- ii) jsize4)])
          (for ([m (in-range 5)])
            (let* ([mi4 (fx* m isize4)]
                   [dmi4 (fx+ di mi4)]
                   [smi4 (fx+ si- mi4)])
            (for ([n (in-range 5)])
              (f! lhs (fx+ n dmi4) (fl- (fl+ (fl* tmp2 (fr fjac (fx+ n smi4)))
                                       (fl* tmp1 (fr njac (fx+ n smi4))))))
            )))
          (f!- lhs (fx+ 0 (fx* 0 isize4) di) dtd_1t_1)
          (f!- lhs (fx+ 1 (fx* 1 isize4) di) dtd_2t_1)
          (f!- lhs (fx+ 2 (fx* 2 isize4) di) dtd_3t_1)
          (f!- lhs (fx+ 3 (fx* 3 isize4) di) dtd_4t_1)
          (f!- lhs (fx+ 4 (fx* 4 isize4) di) dtd_5t_1))

        (let ([di (fx+ (fx* 1 jsize4) (fx* ii ksize4))]
              [si= (fx* ii jsize4)])
          (for ([m (in-range 5)])
            (let* ([mi4 (fx* m isize4)]
                   [dmi4 (fx+ mi4 di)]
                   [smi4 (fx+ mi4 si=)])
            (for ([n (in-range 5)])
              (f! lhs (fx+ n dmi4) (fl* 2.0 tmp1 (fr njac (fx+ n smi4))))

            )))
          (f!+ lhs (fx+ 0 (fx* 0 isize4) di) dtd_1t_1*2+1)
          (f!+ lhs (fx+ 1 (fx* 1 isize4) di) dtd_2t_1*2+1)
          (f!+ lhs (fx+ 2 (fx* 2 isize4) di) dtd_3t_1*2+1)
          (f!+ lhs (fx+ 3 (fx* 3 isize4) di) dtd_4t_1*2+1)
          (f!+ lhs (fx+ 4 (fx* 4 isize4) di) dtd_5t_1*2+1))

        (let ([di (fx+ (fx* 2 jsize4) (fx* ii ksize4))]
              [si+ (fx* (fx++ ii) jsize4)])
          (for ([m (in-range 5)])
            (let* ([mi4 (fx* m isize4)]
                   [dmi4 (fx+ mi4 di)]
                   [smi4 (fx+ mi4 si+)])
            (for ([n (in-range 5)])
              (f! lhs (fx+ n dmi4) (fl- (fl* tmp2 (fr fjac (fx+ n smi4)))
                                    (fl* tmp1 (fr njac (fx+ n smi4))))))))
          (f!- lhs (fx+ 0 (fx* 0 isize4) di) dtd_1t_1)
          (f!- lhs (fx+ 1 (fx* 1 isize4) di) dtd_2t_1)
          (f!- lhs (fx+ 2 (fx* 2 isize4) di) dtd_3t_1)
          (f!- lhs (fx+ 3 (fx* 3 isize4) di) dtd_4t_1)
          (f!- lhs (fx+ 4 (fx* 4 isize4) di) dtd_5t_1))))


      ; gaussian elimination 
      (define-syntax-rule (IDX22 I) (fx+ (fx* I iisize2) kkjjsize2))
    
      (define ccj4 (fx* 2 jsize4))
      (binvcrhs lhs jsize4
                lhs ccj4
                rhs kkjjsize2)

      (for ([ii (in-range 1 IISIZE)])
        (let* ([ijk2 (IDX22 ii)]
               [ik4 (fx* ii ksize4)]
               [bi4 (fx+ jsize4 ik4)]
               [ai4 ik4] 
               [cj4 (fx+ ccj4 ik4)])

        (matvec_sub lhs ai4
                    rhs (fx+ (fx* (fx- ii 1) iisize2) kkjjsize2)
                    rhs ijk2)

        (matmul_sub lhs ai4
                    lhs (fx- cj4 ksize4)
                    lhs bi4)

        (binvcrhs lhs bi4 
                  lhs cj4
                  rhs ijk2)))

      (let* ([Ik4 (fx* IISIZE ksize4)]
             [Ijk4 (fx+ jsize4 Ik4)]
             [IDX2IISIZE (IDX22 IISIZE)])

      (matvec_sub lhs Ik4
                  rhs (IDX22 (fx- IISIZE 1))
                  rhs IDX2IISIZE)

      (matmul_sub lhs Ik4
                  lhs (fx+ ccj4 (fx- Ik4 ksize4))
                  lhs Ijk4)

      (binvrhs    lhs Ijk4
                  rhs IDX2IISIZE))

      (for ([ii (in-range (sub1 IISIZE) -1 -1)])
        (let* ([BLOCK_SIZE 5]
               [iicc (fx+ ccj4 (fx* ii ksize4))]
               [idx2 (IDX22 ii)]
               [idx2+1 (fx+ idx2 iisize2)])
        (for ([m (in-range BLOCK_SIZE)])
          (let ([midx (fx+ m idx2)]
                [miicc (fx+ m iicc)])
            (f! rhs midx
              (for/fold ([x (fr rhs midx)]) ([n (in-range BLOCK_SIZE)])
                (fl- x 
                     (fl* (fr lhs (fx+ miicc (fx* n isize4))) 
                          (fr rhs (fx+ n idx2+1)))))))))))))))

(__solve x_solve 1)
(__solve y_solve 2)
(__solve z_solve 3)

(define (checkSum arr nz2 ny2 nx2 isize1 jsize1 ksize1)
  (for*/fold ([csum 0.0]) ([k (in-range (add1 nz2))]
         [j (in-range (add1 ny2))]
         [i (in-range (add1 nx2))]
         [m (in-range 5)])
    (let* ([offset (+ m (* i isize1) (* j jsize1) (* k ksize1))]
           [arro (fr arr offset)])
      (+ csum (/ (flsqr arro) (* (+ 2 nz2) (+ 2 ny2) (+ 2 nx2) 5))))))

(define (get-input-pars maxlevel)
  (define fn "mg.input")
  (if (file-exists? fn)
    (match (call-with-input-file fn read)
      [(list lt lnx lny lnz nit)
        (when (lt . > . maxlevel)
          (printf "lt=~a Maximum allowable=~a\n" lt maxlevel)
          (exit 0))
        (values nit lt lnx lnz)]
      [else 
        (printf "Error reading from file mg.input\n")
        (exit 0)])
    (printf "No input file mg.input, Using compiled defaults\n")))
