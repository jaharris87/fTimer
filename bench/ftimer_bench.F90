! fTimer performance measurement harness
!
! PURPOSE
! -------
! Establishes reproducible baselines for hot-path and reporting overhead.
! Results identify concrete optimization targets without relying on intuition.
!
! SCENARIOS COVERED
! -----------------
!  1. Flat start/stop (name-based)   -- measures name normalization + segment
!                                       lookup + stack push/pop + clock call
!  2. Flat start/stop (id-based)     -- same path minus name normalization and
!                                       segment lookup; isolates stack cost
!  3-5. Lookup scaling N=1/10/50     -- name-based, measures how the linear
!                                       find_segment_index scan scales with N
!  6-9. Nesting depth 1/5/10/20      -- id-based; each cycle does D pushes +
!                                       D pops; shows call-stack allocation
!                                       churn scaling with nesting depth
! 10-12. get_summary N=10/50/100     -- summary build + self-time pass scaling
!                                       with timer count
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
!   Compare "flat name-based" vs "flat id-based" to isolate name-lookup cost.
!   Compare nesting depths to measure stack push/pop allocation scaling.
!   Compare get_summary timer counts to see summary-generation scaling.

program ftimer_bench
   use, intrinsic :: iso_fortran_env, only: int64, real64
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_init, &
                     ftimer_lookup, ftimer_start, ftimer_start_id, &
                     ftimer_stop, ftimer_stop_id
   use ftimer_types, only: ftimer_summary_t
   implicit none

   integer, parameter :: REPS_HOT = 100000  ! flat and lookup scenarios
   integer, parameter :: REPS_NESTED = 10000   ! per nesting-depth scenario
   integer, parameter :: REPS_SUMMARY = 1000    ! per summary scenario
   integer, parameter :: REPS_SUMMARY_LARGE = 200  ! for 100-timer scenario

   integer(int64) :: count_rate

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
   call bench_lookup_scaling(REPS_HOT/10, 10, count_rate)
   call bench_lookup_scaling(REPS_HOT/50, 50, count_rate)

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
   write (*, '(a)') 'Notes:'
   write (*, '(a)') '  - Nesting "per-op" = per full nest cycle (D pushes + D pops).'
   write (*, '(a)') '  - get_summary "per-op" = per summary build call.'
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
      integer :: i, discard

      call ftimer_init()
      discard = ftimer_lookup('t')  ! pre-register to avoid first-time cost
      call system_clock(t0)
      do i = 1, reps
         call ftimer_start('t')
         call ftimer_stop('t')
      end do
      call system_clock(t1)
      call ftimer_finalize()
      call print_result('flat start/stop (name-based)', reps, t0, t1, count_rate)
      if (discard < 0) write (*, '(a)') ''  ! suppress unused-variable warning
   end subroutine bench_flat_name

   ! Scenario 2: id-based start/stop, pre-registered timer.
   ! No name normalization, no segment lookup. Isolates pure stack push/pop
   ! and clock-call cost from the name-lookup cost in scenario 1.
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
   ! Cycles through all N timers each outer rep.  Each inner start/stop
   ! exercises find_segment_index which does a linear scan over all segments.
   ! Comparing N=1, 10, 50 shows how scan cost scales with timer count.
   subroutine bench_lookup_scaling(reps_outer, num_timers, count_rate)
      integer, intent(in) :: reps_outer
      integer, intent(in) :: num_timers
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer :: i, j, total_ops, discard
      character(len=8) :: tname
      character(len=47) :: label

      total_ops = reps_outer*num_timers
      call ftimer_init()
      do j = 1, num_timers
         write (tname, '("t",i7.7)') j
         discard = ftimer_lookup(tname)  ! pre-register all timers
      end do
      if (discard < 0) write (*, '(a)') ''  ! suppress unused-variable warning
      call system_clock(t0)
      do i = 1, reps_outer
         do j = 1, num_timers
            write (tname, '("t",i7.7)') j
            call ftimer_start(tname)
            call ftimer_stop(tname)
         end do
      end do
      call system_clock(t1)
      call ftimer_finalize()
      write (label, '("lookup scaling N=",i2," timers (name-based)")') num_timers
      call print_result(trim(label), total_ops, t0, t1, count_rate)
   end subroutine bench_lookup_scaling

   ! Scenarios 6-9: id-based nesting at increasing depths.
   ! Each cycle does D id-based starts then D id-based stops.
   ! Using id-based ops isolates the call-stack push/pop allocation churn
   ! from name-lookup cost.  Each push allocates a new array of size depth+1
   ! and copies; each pop allocates a new array of size depth-1 and copies.
   ! Comparing depths 1, 5, 10, 20 shows how allocation churn scales with D.
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
   ! calling get_summary().  The summary build traverses all segments, computes
   ! self-times (O(N^2) pass), and allocates the entries array.
   ! Comparing N=10, 50, 100 reveals the scaling behavior.
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
