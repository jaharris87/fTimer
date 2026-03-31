! fTimer performance measurement harness
!
! PURPOSE
! -------
! Establishes reproducible baselines for hot-path and reporting overhead.
! Results identify concrete optimization targets without relying on intuition.
!
! SCENARIOS COVERED
! -----------------
!  1. Flat start/stop (name-based)   -- measures name normalization + mapped
!                                       lookup + stack push/pop + clock call
!  2. Flat start/stop (id-based)     -- same path minus name normalization and
!                                       mapped lookup; isolates stack cost
!  3-5. Lookup scaling N=1/100/1000  -- name-based, shows whether steady-state
!                                       mapped lookup stays near-flat as the
!                                       resident timer set grows
!  6-9. Nesting depth 1/5/10/20      -- id-based; each cycle does D pushes +
!                                       D pops; shows stack bookkeeping cost
!                                       scaling with nesting depth
! 10-12. get_summary N=10/50/100     -- summary build scaling with timer count
! 13-15. build_summary N=10/50/100   -- direct local summary construction on
!                                       prebuilt flat segments; isolates the
!                                       tree build/allocation work from the
!                                       wrapper's timestamp capture
! 16. raw date string formatting     -- date_and_time + string formatting,
!                                       matching the original per-call wrapper
! 17. ftimer_date_string steady-state -- cached second-resolution date stamp
!                                        path used by get_summary/print/write
!
! METRICS
!   Reps       number of operations (start/stop pairs or summary calls)
!   Total(ms)  wall time for the entire scenario
!   Per-op(ns) average cost per operation
!   For nesting, one "op" = one full nest cycle (D pushes + D pops).
!
! HOW TO RUN
!   cmake --fresh -B build-bench -DFTIMER_BUILD_BENCH=ON
!   cmake --build build-bench --target ftimer_bench
!   ./build-bench/bench/ftimer_bench
!
! INTERPRETATION
!   Compare "flat name-based" vs "flat id-based" to isolate the remaining
!   difference between ergonomic name-based timing and the optional cached-id
!   hot path.
!   Compare nesting depths to measure stack push/pop scaling after context
!   warm-up has removed first-growth effects.
!   Compare lookup-scaling rows to confirm the mapped name path stays much
!   flatter than the old linear-scan baseline as timer count grows.
!   Compare get_summary timer counts to see summary-generation scaling.

program ftimer_bench
   use, intrinsic :: iso_fortran_env, only: int64, real64
   use ftimer_clock, only: ftimer_date_string
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_init, &
                     ftimer_lookup, ftimer_start, ftimer_start_id, &
                     ftimer_stop, ftimer_stop_id
   use ftimer_summary, only: build_summary
   use ftimer_types, only: ftimer_segment_t, ftimer_summary_t, wp
   implicit none

   integer, parameter :: REPS_HOT = 100000  ! flat and lookup scenarios
   integer, parameter :: REPS_NESTED = 10000   ! per nesting-depth scenario
   integer, parameter :: REPS_SUMMARY = 1000    ! per summary scenario (N=10, N=50)
   ! Reduced rep count for N=100: get_summary at 100 timers is ~40x slower than
   ! at 10 timers (superlinear scaling), so 200 reps still gives ~40ms total.
   integer, parameter :: REPS_SUMMARY_LARGE = 200  ! for 100-timer scenario
   integer, parameter :: REPS_DATE_RAW = 5000
   integer, parameter :: REPS_DATE_CACHED = 100000
   character(len=40), parameter :: BENCH_DATE = '2026-03-27 12:00:00 -0400'

   integer(int64) :: count_rate
   integer :: date_string_sink = 0

   call system_clock(count_rate=count_rate)

   write (*, '(a)') '=== fTimer Performance Benchmark ==='
   write (*, '(a)') ''
   write (*, '(a47,a10,a12,a13)') &
      'Benchmark                                      ', &
      '      Reps', '  Total(ms)', '  Per-op(ns)'
   write (*, '(a82)') repeat('-', 82)

   ! --- Hot-path scenarios ---
   call bench_flat_name(REPS_HOT, count_rate)
   call bench_flat_id(REPS_HOT, count_rate)

   write (*, '(a)') ''

   ! --- Lookup scaling scenarios ---
   call bench_lookup_scaling(REPS_HOT, 1, count_rate)
   call bench_lookup_scaling(REPS_HOT/100, 100, count_rate)
   call bench_lookup_scaling(REPS_HOT/1000, 1000, count_rate)

   write (*, '(a)') ''

   ! --- Nesting-depth (call-stack push/pop churn) scenarios ---
   call bench_nesting(REPS_NESTED, 1, count_rate)
   call bench_nesting(REPS_NESTED, 5, count_rate)
   call bench_nesting(REPS_NESTED, 10, count_rate)
   call bench_nesting(REPS_NESTED, 20, count_rate)

   write (*, '(a)') ''

   ! --- Summary-generation scaling scenarios ---
   call bench_summary(10, REPS_SUMMARY, count_rate)
   call bench_summary(50, REPS_SUMMARY, count_rate)
   call bench_summary(100, REPS_SUMMARY_LARGE, count_rate)

   write (*, '(a)') ''

   ! --- Direct summary-construction scenarios ---
   call bench_build_summary_direct(10, REPS_SUMMARY, count_rate)
   call bench_build_summary_direct(50, REPS_SUMMARY, count_rate)
   call bench_build_summary_direct(100, REPS_SUMMARY_LARGE, count_rate)

   write (*, '(a)') ''

   ! --- Date formatting / cache scenarios ---
   call bench_raw_date_string(REPS_DATE_RAW, count_rate)
   call bench_cached_date_string(REPS_DATE_CACHED, count_rate)

   write (*, '(a)') ''
   write (*, '(a)') 'Notes:'
   write (*, '(a)') '  - Nesting "per-op" = per full nest cycle (D pushes + D pops).'
   write (*, '(a)') '  - get_summary "per-op" = per summary build call.'
   write (*, '(a)') '  - build_summary (direct) uses prebuilt flat segments and fixed dates.'
   write (*, '(a)') '  - raw date string = uncached date_and_time + formatting.'
   write (*, '(a)') '  - ftimer_date_string steady-state = cached path after warm-up.'
   write (*, '(a)') '  - name-based start/stop remains the default path; lookup/start_id/stop_id is the optional hot path.'
   write (*, '(a)') '  - All scenarios use the real wall-clock (no mock clock).'
   write (*, '(a)') '  - Timings include clock-call overhead inside start/stop.'

contains

   ! Scenario 1: name-based start/stop, single timer, steady-state loop.
   ! Pre-registers the timer with ftimer_lookup before timing to ensure the
   ! segment exists; the hot loop then always hits the existing segment.
   subroutine bench_flat_name(reps, count_rate)
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer :: i

      call ftimer_init()
      i = ftimer_lookup('t')  ! pre-register to avoid first-time cost
      call system_clock(t0)
      do i = 1, reps
         call ftimer_start('t')
         call ftimer_stop('t')
      end do
      call system_clock(t1)
      call ftimer_finalize()
      call print_result('flat start/stop (name-based)', reps, t0, t1, count_rate)
   end subroutine bench_flat_name

   ! Scenario 2: id-based start/stop, pre-registered timer.
   ! No name normalization, no segment lookup. Isolates pure stack push/pop
   ! and clock-call cost from the mapped-lookup cost in scenario 1.
   subroutine bench_flat_id(reps, count_rate)
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer :: i, id

      call ftimer_init()
      id = ftimer_lookup('t')
      call system_clock(t0)
      do i = 1, reps
         call ftimer_start_id(id)
         call ftimer_stop_id(id)
      end do
      call system_clock(t1)
      call ftimer_finalize()
      call print_result('flat start/stop (id-based)', reps, t0, t1, count_rate)
   end subroutine bench_flat_id

   ! Scenarios 3-5: name-based lookup with N unique timers.
   ! Cycles through all N timers each outer rep. Each inner start/stop uses
   ! the same public name-based path as production code, but with a large
   ! resident timer set already registered. Comparing N=1, 100, 1000 shows
   ! whether the internal name map keeps steady-state lookup near-flat.
   !
   ! Timer names are built into an array before timing begins so that
   ! formatted write overhead does not contaminate the hot-loop measurement.
   subroutine bench_lookup_scaling(reps_outer, num_timers, count_rate)
      integer, intent(in) :: reps_outer
      integer, intent(in) :: num_timers
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer :: i, j, total_ops
      character(len=8), allocatable :: tnames(:)
      character(len=47) :: label

      total_ops = reps_outer*num_timers
      allocate (tnames(num_timers))
      call ftimer_init()
      do j = 1, num_timers
         write (tnames(j), '("t",i7.7)') j
         i = ftimer_lookup(tnames(j))  ! pre-register all timers
      end do
      call system_clock(t0)
      do i = 1, reps_outer
         do j = 1, num_timers
            call ftimer_start(tnames(j))
            call ftimer_stop(tnames(j))
         end do
      end do
      call system_clock(t1)
      call ftimer_finalize()
      deallocate (tnames)
      write (label, '("lookup scaling N=",i0," timers (name-based)")') num_timers
      call print_result(trim(label), total_ops, t0, t1, count_rate)
   end subroutine bench_lookup_scaling

   ! Scenarios 6-9: id-based nesting at increasing depths.
   ! Each cycle does D id-based starts then D id-based stops.
   ! Using id-based ops isolates call-stack bookkeeping cost from
   ! name-lookup cost.  After the warm-up cycle has grown the stack to the
   ! required depth, steady-state reps reuse the existing capacity.
   ! Comparing depths 1, 5, 10, 20 shows how the remaining stack overhead
   ! scales with D.
   subroutine bench_nesting(reps, depth, count_rate)
      integer, intent(in) :: reps
      integer, intent(in) :: depth
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer, allocatable :: ids(:)
      integer :: d, i
      character(len=8) :: tname
      character(len=47) :: label

      call ftimer_init()
      allocate (ids(depth))
      do d = 1, depth
         write (tname, '("t",i7.7)') d
         ids(d) = ftimer_lookup(tname)
      end do

      ! Warm up: one full cycle to create all contexts
      do d = 1, depth
         call ftimer_start_id(ids(d))
      end do
      do d = depth, 1, -1
         call ftimer_stop_id(ids(d))
      end do

      call system_clock(t0)
      do i = 1, reps
         do d = 1, depth
            call ftimer_start_id(ids(d))
         end do
         do d = depth, 1, -1
            call ftimer_stop_id(ids(d))
         end do
      end do
      call system_clock(t1)
      call ftimer_finalize()
      deallocate (ids)
      write (label, '("nesting depth",i3," (id-based, per cycle)")') depth
      call print_result(trim(label), reps, t0, t1, count_rate)
   end subroutine bench_nesting

   ! Scenarios 10-12: get_summary overhead with N flat timers.
   ! Creates N timers each called once, then measures the cost of repeatedly
   ! calling get_summary().  The summary build walks the visible timer tree,
   ! computes self-times from direct children, and allocates the entries array.
   ! Comparing N=10, 50, 100 reveals the remaining scaling behavior.
   subroutine bench_summary(num_timers, reps, count_rate)
      integer, intent(in) :: num_timers
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer :: i, j
      character(len=8) :: tname
      character(len=47) :: label
      type(ftimer_summary_t) :: summary

      call ftimer_init()
      do j = 1, num_timers
         write (tname, '("t",i7.7)') j
         call ftimer_start(tname)
         call ftimer_stop(tname)
      end do

      call system_clock(t0)
      do i = 1, reps
         call ftimer_get_summary(summary)
      end do
      call system_clock(t1)
      call ftimer_finalize()
      write (label, '("get_summary N=",i3," timers")') num_timers
      call print_result(trim(label), reps, t0, t1, count_rate)
   end subroutine bench_summary

   subroutine bench_build_summary_direct(num_timers, reps, count_rate)
      integer, intent(in) :: num_timers
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0
      integer(int64) :: t1
      integer :: i
      character(len=47) :: label
      type(ftimer_segment_t), allocatable :: segments(:)
      type(ftimer_summary_t) :: summary

      call build_flat_segments(segments, num_timers)

      call system_clock(t0)
      do i = 1, reps
         call build_summary(summary=summary, segments=segments, init_wtime=0.0_wp, init_date=BENCH_DATE, &
                            end_time=real(num_timers, wp), end_date=BENCH_DATE)
      end do
      call system_clock(t1)

      if (allocated(segments)) deallocate (segments)

      write (label, '("build_summary N=",i3," timers (direct)")') num_timers
      call print_result(trim(label), reps, t0, t1, count_rate)
   end subroutine bench_build_summary_direct

   subroutine bench_raw_date_string(reps, count_rate)
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0
      integer(int64) :: t1
      integer :: i

      call system_clock(t0)
      do i = 1, reps
         call consume_date_string(raw_date_string())
      end do
      call system_clock(t1)

      call print_result('raw date string formatting', reps, t0, t1, count_rate)
   end subroutine bench_raw_date_string

   subroutine bench_cached_date_string(reps, count_rate)
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0
      integer(int64) :: t1
      integer :: i

      call consume_date_string(ftimer_date_string())

      call system_clock(t0)
      do i = 1, reps
         call consume_date_string(ftimer_date_string())
      end do
      call system_clock(t1)

      call print_result('ftimer_date_string steady-state', reps, t0, t1, count_rate)
   end subroutine bench_cached_date_string

   subroutine build_flat_segments(segments, num_timers)
      type(ftimer_segment_t), allocatable, intent(out) :: segments(:)
      integer, intent(in) :: num_timers
      integer :: i
      character(len=8) :: tname

      allocate (segments(num_timers))
      do i = 1, num_timers
         write (tname, '("t",i7.7)') i
         segments(i)%name = tname
         segments(i)%contexts%count = 1
         allocate (segments(i)%contexts%stacks(1))
         allocate (segments(i)%time(1))
         allocate (segments(i)%start_time(1))
         allocate (segments(i)%is_running(1))
         allocate (segments(i)%call_count(1))
         segments(i)%time(1) = 1.0_wp
         segments(i)%start_time(1) = 0.0_wp
         segments(i)%is_running(1) = .false.
         segments(i)%call_count(1) = 1
      end do
   end subroutine build_flat_segments

   function raw_date_string() result(stamp)
      character(len=40) :: stamp
      character(len=5) :: zone
      integer :: values(8)

      call date_and_time(values=values, zone=zone)
      write (stamp, '(i4.4,"-",i2.2,"-",i2.2," ",i2.2,":",i2.2,":",i2.2," ",a)') &
         values(1), values(2), values(3), values(5), values(6), values(7), zone
   end function raw_date_string

   subroutine consume_date_string(stamp)
      character(len=*), intent(in) :: stamp
      date_string_sink = date_string_sink + len_trim(stamp)
   end subroutine consume_date_string

   subroutine print_result(label, reps, t0, t1, count_rate)
      character(len=*), intent(in) :: label
      integer, intent(in) :: reps
      integer(int64), intent(in) :: t0, t1, count_rate
      real(real64) :: total_ms, per_op_ns

      total_ms = real(t1 - t0, real64)/real(count_rate, real64)*1.0d3
      per_op_ns = real(t1 - t0, real64)/real(count_rate, real64) &
                  /real(reps, real64)*1.0d9
      write (*, '(a47,i10,f12.2,f13.1)') label, reps, total_ms, per_op_ns
   end subroutine print_result

end program ftimer_bench
