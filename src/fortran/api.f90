module api
    use, intrinsic :: iso_c_binding, only: c_float, c_int
    implicit none
contains

    subroutine set_airfoil(x_in, y_in, n_in) bind(c, name='set_airfoil')
        use m_xgeom, only: geopar, norm
        use m_spline, only: seval, segspl, scalc
        use m_xgdes, only: abcopy
        use m_xgeom, only: cang
        use i_xfoil

        integer(c_int), intent(in) :: n_in
        real(c_float), intent(in) :: x_in(n_in), y_in(n_in)

        ! Local variables
        !
        real :: area, xble, xbte, xinl, xout, xtmp, yble, ybot, ybte, ytmp, ytop, amax, angtol
        integer :: i, ip, kdot, lu, imax, Itype

        data angtol/40.0/

        do i=1, n_in
            XB(i) = x_in(i)
            YB(i) = y_in(i)
        end do
        NB = n_in

        !---- calculate airfoil area assuming counterclockwise ordering
        area = 0.0
        do i = 1, NB
            ip = i + 1
            if (i==NB) ip = 1
            area = area + 0.5 * (YB(i) + YB(ip)) * (XB(i) - XB(ip))
        enddo
        !
        if (area>=0.0) then
            LCLock = .false.
            write (*, 99001) NB
            !...............................................................
            99001 format (/' Number of input coordinate points:', i4/' Counterclockwise ordering')
        else
            !----- if area is negative (clockwise order), reverse coordinate order
            LCLock = .true.
            write (*, 99002) NB
            99002 format (/' Number of input coordinate points:', i4/' Clockwise ordering')
            do i = 1, NB / 2
                xtmp = XB(NB - i + 1)
                ytmp = YB(NB - i + 1)
                XB(NB - i + 1) = XB(i)
                YB(NB - i + 1) = YB(i)
                XB(i) = xtmp
                YB(i) = ytmp
            enddo
        endif
        !
        if (LNOrm) then
            call norm(XB, XBP, YB, YBP, SB, NB)
            write (*, 99003)
            99003 format (/' Airfoil has been normalized')
        endif
        !
        call scalc(XB, YB, SB, NB)
        call segspl(XB, XBP, SB, NB)
        call segspl(YB, YBP, SB, NB)
        !
        call geopar(XB, XBP, YB, YBP, SB, NB, W1, SBLe, CHOrdb, AREab, &
                RADble, ANGbte, EI11ba, EI22ba, APX1ba, APX2ba, EI11bt, EI22bt, APX1bt, &
                & APX2bt, THIckb, CAMbrb)
        !
        xble = seval(SBLe, XB, XBP, SB, NB)
        yble = seval(SBLe, YB, YBP, SB, NB)
        xbte = 0.5 * (XB(1) + XB(NB))
        ybte = 0.5 * (YB(1) + YB(NB))
        !
        write (*, 99004) xble, yble, CHOrdb, xbte, ybte
        99004 format (/'  LE  x,y  =', 2F10.5, '  |   Chord =', f10.5/'  TE  x,y  =', 2F10.5, '  |')
        !
        !---- set reasonable MSES domain parameters for non-MSES coordinate file
        if (Itype<=2 .and. ISPars==' ') then
            xble = seval(SBLe, XB, XBP, SB, NB)
            yble = seval(SBLe, YB, YBP, SB, NB)
            xinl = xble - 2.0 * CHOrdb
            xout = xble + 3.0 * CHOrdb
            ybot = yble - 2.5 * CHOrdb
            ytop = yble + 3.5 * CHOrdb
            xinl = aint(20.0 * abs(xinl / CHOrdb) + 0.5) / 20.0 * sign(CHOrdb, xinl)
            xout = aint(20.0 * abs(xout / CHOrdb) + 0.5) / 20.0 * sign(CHOrdb, xout)
            ybot = aint(20.0 * abs(ybot / CHOrdb) + 0.5) / 20.0 * sign(CHOrdb, ybot)
            ytop = aint(20.0 * abs(ytop / CHOrdb) + 0.5) / 20.0 * sign(CHOrdb, ytop)
            write (ISPars, 99005) xinl, xout, ybot, ytop
            99005 format (1x, 4F8.2)
        endif
        !
        !---- wipe out old flap hinge location
        XBF = 0.0
        YBF = 0.0
        LBFlap = .false.
        !
        !---- wipe out off-design alphas, CLs
        !c      NALOFF = 0
        !c      NCLOFF = 0
        !

        call abcopy(.true.)
        !
        call cang(X, Y, N, 0, imax, amax)
        if (abs(amax)>angtol) write (*, 99007) amax, imax
        99007 format (/' WARNING: Poor input coordinate distribution'/'          Excessive panel angle', f7.1, '  at i =', &
                &i4/'          Repaneling with PANE and/or PPAR suggested'/                                                &
                &'           (doing GDES,CADD before repaneling _may_'/'            improve excessively coarse LE spacing')
    end subroutine set_airfoil

    subroutine set_conditions(Re, M) bind(c, name='set_conditions')
        use s_xfoil, only: comset, cpcalc, clcalc, cdcalc
        use i_xfoil
        real(c_float), intent(in) :: Re, M

        if (Re == 0.) then
            LVIsc = .false.
        else
            LVIsc = .true.
        end if

        REInf1 = Re

        LBLini = .false.
        LIPan = .false.

        if (M /= MINf) then
            MINf = M

            call comset
            if (MINf>0.0) write (*, 99003) CPStar, QSTar / QINf
            99003      format (/' Sonic Cp =', f10.2, '      Sonic Q/Qinf =', f10.3/)

            call cpcalc(N, QINv, QINf, MINf, CPI)
            if (LVIsc) call cpcalc(N + NW, QVIs, QINf, MINf, CPV)
            call clcalc(N, X, Y, GAM, GAM_a, ALFa, MINf, QINf, XCMref, YCMref, CL, CM, CDP, CL_alf, CL_msq)
            call cdcalc
        end if

        LVConv = .false.
    end subroutine set_conditions

    subroutine get_conditions(Re, M) bind(c, name='get_conditions')
        use i_xfoil, only: REInf1, MINf
        real(c_float), intent(out) :: Re, M
        Re = REInf1
        M = MINf
    end subroutine get_conditions

    subroutine set_max_iter(max_iter) bind(c, name='set_max_iter')
        use i_xfoil, only: ITMax
        integer(c_int), intent(in) :: max_iter
        ITMax = max_iter
    end subroutine set_max_iter

    function get_max_iter() bind(c, name='get_max_iter')
        use i_xfoil, only: ITMax
        real(c_float) :: get_max_iter
        get_max_iter = ITMax
    end function get_max_iter

    subroutine reset_bls() bind(c, name='reset_bls')
        use i_xfoil, only: LBLini, LIPan
        LBLini = .not.LBLini
        if (LBLini) then
            write (*, *) 'BLs are assumed to be initialized'
        else
            write (*, *) 'BLs will be initialized on next point'
            LIPan = .false.
        endif
    end subroutine reset_bls

    subroutine alfa_(a_input, cl_out, cd_out, cm_out) bind(c, name='alfa')
        use m_xoper, only: specal, viscal, fcpmin
        use i_xfoil

        real(c_float), intent(in) :: a_input
        real(c_float), intent(out) :: cl_out, cd_out, cm_out
        ADEg = a_input

        ALFa = a_input * DTOr
        QINf = 1.0
        LALfa = .true.
        call specal
        if (abs(ALFa - AWAke)>1.0E-5) LWAke = .false.
        if (abs(ALFa - AVIsc)>1.0E-5) LVConv = .false.
        if (abs(MINf - MVIsc)>1.0E-5) LVConv = .false.
        !
        if (LVIsc) call viscal(ITMax)

        cl_out = CL
        cd_out = CD
        cm_out = CM
    end subroutine alfa_

    subroutine cl_(cl_input, a_out, cd_out, cm_out) bind(c, name='cl')
        use m_xoper, only: speccl, viscal
        use i_xfoil

        real(c_float), intent(in) :: cl_input
        real(c_float), intent(out) :: a_out, cd_out, cm_out

        CLSpec = cl_input
        ALFa = 0.0
        QINf = 1.0
        LALfa = .false.
        call speccl
        ADEg = ALFa / DTOr
        if (abs(ALFa - AWAke)>1.0E-5) LWAke = .false.
        if (abs(ALFa - AVIsc)>1.0E-5) LVConv = .false.
        if (abs(MINf - MVIsc)>1.0E-5) LVConv = .false.

        if (LVIsc) call viscal(ITMax)

        a_out = ALFa / DTOr
        cd_out = CD
        cm_out = CM
    end subroutine cl_

    subroutine aseq(a_start, a_end, n_step, &
                    a_arr, cl_arr, cd_arr, cm_arr) bind(c, name='aseq')
        use m_xoper, only: specal, viscal
        use i_xfoil
        real(c_float), intent(in) :: a_start, a_end
        integer(c_int), intent(in) :: n_step
        real(c_float), dimension(n_step), intent(inout) :: a_arr, cl_arr, cd_arr, cm_arr
        integer :: i, iseqex, itmaxs
        real :: a0, da

        a0 = a_start * DTOr
        da = (a_end - a_start) / float(n_step) * DTOr

        LALfa = .true.

        !----- initialize unconverged-point counter
        iseqex = 0

        do i=1, n_step
            ALFa = a0 + da * float(i - 1)
            if (abs(ALFa - AWAke)>1.0E-5) LWAke = .false.
            if (abs(ALFa - AVIsc)>1.0E-5) LVConv = .false.
            if (abs(MINf - MVIsc)>1.0E-5) LVConv = .false.
            call specal
            itmaxs = ITMax + 5
            if (LVIsc) call viscal(itmaxs)
            ADEg = ALFa / DTOr

            if (LVConv .or. .not.LVIsc) then
                a_arr(i) = ADEg
                cl_arr(i) = CL
                cd_arr(i) = CD
                cm_arr(i) = CM
            elseif (LVIsc .and. .not.LVConv) then
                !-------- increment unconverged-point counter
                iseqex = iseqex + 1
                if (iseqex>=NSEqex) then
                    write (*, 99005) iseqex, a_arr(max(i-1, 0)), cl_arr(max(i-1, 0))
                    99005 format (/' Sequence halted since previous', i3, ' points did not converge'/&
                            ' Last-converged  alpha =', f8.3, '    CL =', f10.5)
                    exit
                endif
            else
                iseqex = 0
            endif
        end do
    end subroutine aseq

    subroutine cseq(cl_start, cl_end, n_step, &
            a_arr, cl_arr, cd_arr, cm_arr) bind(c, name='cseq')
        use m_xoper, only: specal, viscal, speccl
        use i_xfoil
        real(c_float), intent(in) :: cl_start, cl_end
        integer(c_int), intent(in) :: n_step
        real(c_float), dimension(n_step), intent(inout) :: a_arr, cl_arr, cd_arr, cm_arr
        integer :: i, iseqex, itmaxs
        real :: cl0, dcl

        cl0 = cl_start
        dcl = (cl_end - cl_start) / float(n_step)
        LALfa = .false.

        !----- initialize unconverged-point counter
        iseqex = 0

        do i=1, n_step
            CLSpec = cl0 + dcl * float(i - 1)
            call speccl
            if (abs(ALFa - AWAke)>1.0E-5) LWAke = .false.
            if (abs(ALFa - AVIsc)>1.0E-5) LVConv = .false.
            if (abs(MINf - MVIsc)>1.0E-5) LVConv = .false.

            itmaxs = ITMax + 5
            if (LVIsc) call viscal(itmaxs)
            ADEg = ALFa / DTOr

            if (LVConv) then
                a_arr(i) = ADEg
                cl_arr(i) = CL
                cd_arr(i) = CD
                cm_arr(i) = CM
            else
                !-------- increment unconverged-point counter
                iseqex = iseqex + 1
                if (iseqex>=NSEqex) then
                    write (*, 99005) iseqex, a_arr(max(i-1, 0)), cl_arr(max(i-1, 0))
                    99005 format (/' Sequence halted since previous', i3, ' points did not converge'/&
                            ' Last-converged  alpha =', f8.3, '    CL =', f10.5)
                    exit
                endif
            endif
        end do
    end subroutine cseq

end module api