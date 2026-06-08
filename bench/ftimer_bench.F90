! fTimer performance measurement harness
!
! PURPOSE
! -------
! Establishes reproducible baselines for hot-path and reporting overhead.
! Results identify concrete optimization targets without relying on intuition.
!
! SCENARIOS COVERED
! -----------------
!  Flat start/stop (name-based)      -- measures name normalization + mapped
!                                       lookup + stack push/pop + clock call
!  Flat start/stop (id-based)        -- same path minus name normalization and
!                                       mapped lookup; isolates stack cost
!  Long-name hot path L=64/256/1024
!                                     -- one resident timer with long labels;
!                                       name-based rows include full validation
!                                       and hashing, id-based row shows cached
!                                       lookup behavior for a long label
!  Lookup scaling N=1/10/50/100/1000
!                                     -- name-based; keeps the historical
!                                       comparison points while also showing
!                                       whether steady-state mapped lookup
!                                       stays near-flat as the resident timer
!                                       set grows into the larger regimes
!  Timer first-touch N=10/100/1000
!                                     -- new resident timer creation through
!                                       lookup; names are prebuilt so this
!                                       isolates internal allocation, growth,
!                                       and index insertion from formatting;
!                                       each row uses one long timed batch of
!                                       independent initialized timer objects
!  Context first-touch C=10/100/1000
!                                     -- one hot timer first observed under
!                                       many parent stacks; parent timers and
!                                       parent root contexts are warmed first
!                                       to isolate new work-context creation;
!                                       each row uses one long timed batch of
!                                       independent initialized timer objects
!  Context scaling C=1/10/50/100/500/1000
!                                     -- one hot timer reused under many parent
!                                        stacks; name-based rows measure the
!                                        default path under growing context
!                                        counts and id-based rows isolate the
!                                        per-segment parent-stack lookup
!  Nesting depth 1/5/10/20           -- id-based; each cycle does D pushes +
!                                       D pops; shows stack bookkeeping cost
!                                       scaling with nesting depth
!  get_summary N=10/50/100           -- summary build scaling with timer count
!  build_summary N=10/50/100         -- direct local summary construction on
!                                       prebuilt flat segments; isolates the
!                                       tree build/allocation work from the
!                                       wrapper's timestamp capture
!  Reporting scale                   -- local text, local CSV, sparse-union
!                                       text, long-name reports, and
!                                       metadata-heavy report output
!  strict MPI CSV reporting          -- MPI-enabled builds only; captures the
!                                       reduction + root CSV reporting path
!  ftimer_openmp serial lane         -- id-first explicit OpenMP object path in
!                                       serial context
!  ftimer_openmp region open/close   -- OpenMP-enabled builds only; captures
!                                       timed-region token overhead
!  ftimer_openmp worker lane         -- OpenMP-enabled builds only; captures
!                                       warmed id-first worker start/stop
!  ftimer_openmp worker ctx C=...    -- OpenMP-enabled builds only; captures
!                                       warmed worker context lookup for one
!                                       timer reused under many parent stacks
!  ftimer_openmp catalog register/lookup
!                                    -- serial-context catalog scaling for many
!                                       registered worker-timing ids
!  ftimer_openmp worker lanes L=...  -- OpenMP-enabled builds only; captures
!                                       concurrent multi-lane worker timing
!  ftimer_openmp worker split L=...  -- OpenMP-enabled builds only; compares
!                                       shared dense lane records with one
!                                       timer object per participating lane
!  ftimer_openmp lane touch K=...    -- OpenMP-enabled builds only; compares
!                                       lazy per-participating-lane first touch
!                                       under small vs large configured capacity
!  raw date string formatting        -- date_and_time + string formatting,
!                                       matching the original per-call wrapper
!  ftimer_date_string steady-state   -- cached second-resolution date stamp
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
!   ./build-bench/bench/ftimer_bench /tmp/ftimer_bench_results.csv
!
! The optional first argument writes parseable CSV benchmark results for trend
! review or archival. It intentionally records observations only, not pass/fail
! thresholds.
! The report-writing rows use per-run scratch files in the system temporary
! directory and delete only those scratch files when the rows complete.
!
! INTERPRETATION
!   Compare "flat name-based" vs "flat id-based" to isolate the remaining
!   difference between ergonomic name-based timing and the optional cached-id
!   hot path.
!   Compare nesting depths to measure stack push/pop scaling after context
!   warm-up has removed first-growth effects.
!   Compare lookup-scaling rows to confirm the mapped name path stays much
!   flatter than the old linear-scan baseline as timer count grows.
!   Compare first-touch rows to measure the allocation/growth cost that users
!   can avoid today only by warming known timers and contexts before a measured
!   timestep.
!   Compare context-scaling rows to quantify the per-segment parent-stack cost
!   when one timer is reused under many distinct parent stacks.
!   Compare get_summary timer counts to see summary-generation scaling.

program ftimer_bench
   use, intrinsic :: iso_c_binding, only: c_int
   use, intrinsic :: iso_fortran_env, only: error_unit, int64, real64
   use ftimer_clock, only: ftimer_date_string
   use ftimer_core, only: ftimer_t
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_init, &
                     ftimer_lookup, ftimer_start, ftimer_start_id, &
                     ftimer_stop, ftimer_stop_id
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_parallel_region_t, &
                            ftimer_openmp_summary_t, ftimer_openmp_t
   use ftimer_summary, only: build_summary, format_mpi_union_summary, format_summary
   use ftimer_types, only: FTIMER_SUCCESS, ftimer_metadata_t, ftimer_mpi_union_summary_t, &
                           ftimer_segment_t, ftimer_summary_t, wp
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Barrier, MPI_COMM_WORLD, MPI_Comm_rank, MPI_Comm_size, MPI_Finalize, &
                      MPI_Init
#endif
#ifdef FTIMER_USE_OPENMP
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
#endif
   implicit none

   interface
      function c_getpid() bind(C, name="getpid") result(pid)
         import :: c_int
         integer(c_int) :: pid
      end function c_getpid
   end interface

   integer, parameter :: REPS_HOT = 100000  ! flat and lookup scenarios
   integer, parameter :: REPS_OPENMP_REGION = 10000
   integer, parameter :: REPS_OPENMP_WORKER = 50000
   integer, parameter :: REPS_LONG_NAME = 50000
   integer, parameter :: REPS_NESTED = 10000   ! per nesting-depth scenario
   integer, parameter :: REPS_SUMMARY = 1000    ! per summary scenario (N=10, N=50)
   ! Reduced rep count for N=100: get_summary at 100 timers is ~40x slower than
   ! at 10 timers (superlinear scaling), so 200 reps still gives ~40ms total.
   integer, parameter :: REPS_SUMMARY_LARGE = 200  ! for 100-timer scenario
   integer, parameter :: REPS_DATE_RAW = 5000
   integer, parameter :: REPS_DATE_CACHED = 100000
   integer, parameter :: REPS_REPORT = 25
   integer, parameter :: REPS_REPORT_LARGE = 5
   integer, parameter :: REPS_CSV_REPORT = 5
   integer, parameter :: REPS_METADATA_REPORT = 10
   integer, parameter :: REPS_MPI_REPORT = 5
   integer, parameter :: REPORT_N_SMALL = 100
   integer, parameter :: REPORT_N_LARGE = 1000
   integer, parameter :: REPORT_LONG_NAME_LEN = 256
   integer, parameter :: REPORT_METADATA_COUNT = 200
   character(len=40), parameter :: BENCH_DATE = '2026-03-27 12:00:00 -0400'

   integer(int64) :: count_rate
   integer :: date_string_sink = 0
   integer(int64) :: text_sink = 0_int64
   integer :: bench_csv_unit = -1
   integer :: bench_nprocs = 1
   integer :: bench_rank = 0
   logical :: bench_csv_enabled = .false.
   logical :: bench_csv_smoke_only = .false.
   character(len=:), allocatable :: bench_csv_path
   character(len=:), allocatable :: local_csv_report_path
   character(len=:), allocatable :: mpi_csv_report_path
#ifdef FTIMER_USE_MPI
   integer :: mpierr
#endif

#ifdef FTIMER_USE_MPI
   call MPI_Init(mpierr)
   call MPI_Comm_rank(MPI_COMM_WORLD, bench_rank, mpierr)
   call MPI_Comm_size(MPI_COMM_WORLD, bench_nprocs, mpierr)
#endif
   call system_clock(count_rate=count_rate)
   call setup_bench_csv()
   call setup_report_scratch_paths()
   call setup_bench_csv_smoke_only()

   call write_bench_line('=== fTimer Performance Benchmark ===')
   call write_bench_line('')
   call write_bench_header()

   if (bench_csv_smoke_only) then
#if defined(FTIMER_USE_MPI) && defined(FTIMER_USE_OPENMP)
      call bench_write_strict_mpi_openmp_csv(1, 1, count_rate)
      call bench_write_sparse_mpi_openmp_union_csv(2, 1, count_rate)
#endif
      call close_bench_csv()
#ifdef FTIMER_USE_MPI
      call MPI_Finalize(mpierr)
#endif
      stop
   end if

   ! --- Hot-path scenarios ---
   call bench_flat_name(REPS_HOT, count_rate)
   call bench_flat_id(REPS_HOT, count_rate)
   call bench_openmp_serial_lane_id(REPS_HOT, count_rate)
#ifdef FTIMER_USE_OPENMP
   call bench_openmp_region_open_close(REPS_OPENMP_REGION, count_rate)
   call bench_openmp_worker_lane_id(REPS_OPENMP_WORKER, count_rate)
   call bench_openmp_worker_context_scaling(REPS_OPENMP_WORKER/10, 10, count_rate)
   call bench_openmp_worker_context_scaling(REPS_OPENMP_WORKER/50, 100, count_rate)
   call bench_openmp_worker_context_scaling(REPS_OPENMP_WORKER/500, 1000, count_rate)
   call bench_openmp_catalog_register(200, 100, count_rate)
   call bench_openmp_catalog_register(50, 1000, count_rate)
   call bench_openmp_catalog_lookup(REPS_OPENMP_WORKER/50, 100, count_rate)
   call bench_openmp_catalog_lookup(REPS_OPENMP_WORKER/500, 1000, count_rate)
   call bench_openmp_worker_lanes(REPS_OPENMP_WORKER, 1, count_rate)
   call bench_openmp_worker_lanes(REPS_OPENMP_WORKER/2, 2, count_rate)
   call bench_openmp_worker_lanes(REPS_OPENMP_WORKER/4, 4, count_rate)
   call bench_openmp_worker_lanes(REPS_OPENMP_WORKER/8, 8, count_rate)
   call bench_openmp_worker_lanes_split(REPS_OPENMP_WORKER/8, 8, count_rate)
   call bench_openmp_lane_first_touch(3, 1000, count_rate)
   call bench_openmp_lane_first_touch(65, 1000, count_rate)
#endif
   call bench_long_name(REPS_LONG_NAME, 64, .false., count_rate)
   call bench_long_name(REPS_LONG_NAME, 256, .false., count_rate)
   call bench_long_name(REPS_LONG_NAME, 1024, .false., count_rate)
   call bench_long_name(REPS_LONG_NAME, 1024, .true., count_rate)

   call write_bench_line('')

   ! --- Lookup scaling scenarios ---
   call bench_lookup_scaling(REPS_HOT, 1, count_rate)
   call bench_lookup_scaling(REPS_HOT/10, 10, count_rate)
   call bench_lookup_scaling(REPS_HOT/50, 50, count_rate)
   call bench_lookup_scaling(REPS_HOT/100, 100, count_rate)
   call bench_lookup_scaling(REPS_HOT/1000, 1000, count_rate)

   call write_bench_line('')

   ! --- First-touch allocation scenarios ---
   call bench_timer_first_touch(1000, 10, count_rate)
   call bench_timer_first_touch(200, 100, count_rate)
   call bench_timer_first_touch(50, 1000, count_rate)
   call bench_context_first_touch(1000, 10, count_rate)
   call bench_context_first_touch(200, 100, count_rate)
   call bench_context_first_touch(50, 1000, count_rate)

   call write_bench_line('')

   ! --- Context-scaling scenarios ---
   call bench_context_scaling_name(REPS_HOT, 1, count_rate)
   call bench_context_scaling_name(REPS_HOT/10, 10, count_rate)
   call bench_context_scaling_name(REPS_HOT/50, 50, count_rate)
   call bench_context_scaling_name(REPS_HOT/100, 100, count_rate)
   call bench_context_scaling_name(REPS_HOT/500, 500, count_rate)
   call bench_context_scaling_name(REPS_HOT/1000, 1000, count_rate)
   call bench_context_scaling_id(REPS_HOT, 1, count_rate)
   call bench_context_scaling_id(REPS_HOT/10, 10, count_rate)
   call bench_context_scaling_id(REPS_HOT/50, 50, count_rate)
   call bench_context_scaling_id(REPS_HOT/100, 100, count_rate)
   call bench_context_scaling_id(REPS_HOT/500, 500, count_rate)
   call bench_context_scaling_id(REPS_HOT/1000, 1000, count_rate)

   call write_bench_line('')

   ! --- Nesting-depth (call-stack push/pop churn) scenarios ---
   call bench_nesting(REPS_NESTED, 1, count_rate)
   call bench_nesting(REPS_NESTED, 5, count_rate)
   call bench_nesting(REPS_NESTED, 10, count_rate)
   call bench_nesting(REPS_NESTED, 20, count_rate)

   call write_bench_line('')

   ! --- Summary-generation scaling scenarios ---
   call bench_summary(10, REPS_SUMMARY, count_rate)
   call bench_summary(50, REPS_SUMMARY, count_rate)
   call bench_summary(100, REPS_SUMMARY_LARGE, count_rate)
#ifdef FTIMER_USE_OPENMP
   call bench_openmp_summary_merge(REPORT_N_SMALL, REPS_REPORT, count_rate)
#endif

   call write_bench_line('')

   ! --- Direct summary-construction scenarios ---
   call bench_build_summary_direct(10, REPS_SUMMARY, count_rate)
   call bench_build_summary_direct(50, REPS_SUMMARY, count_rate)
   call bench_build_summary_direct(100, REPS_SUMMARY_LARGE, count_rate)

   call write_bench_line('')

   ! --- Reporting scale scenarios ---
   call bench_format_local_text(REPORT_N_SMALL, REPS_REPORT, 8, 0, count_rate, &
                                'format local text N=100 entries')
   call bench_format_local_text(REPORT_N_LARGE, REPS_REPORT_LARGE, 8, 0, count_rate, &
                                'format local text N=1000 entries')
   call bench_write_local_csv(REPORT_N_SMALL, REPS_CSV_REPORT, 8, 0, count_rate, &
                              'write local CSV N=100 entries')
   call bench_write_local_csv(REPORT_N_LARGE, REPS_CSV_REPORT, 8, 0, count_rate, &
                              'write local CSV N=1000 entries')
   call bench_format_local_text(REPORT_N_SMALL, REPS_REPORT, REPORT_LONG_NAME_LEN, 0, count_rate, &
                                'format local text N=100 long L=256')
   call bench_format_local_text(REPORT_N_SMALL, REPS_METADATA_REPORT, 8, REPORT_METADATA_COUNT, count_rate, &
                                'format local text metadata M=200')
   call bench_write_local_csv(REPORT_N_SMALL, REPS_METADATA_REPORT, 8, REPORT_METADATA_COUNT, count_rate, &
                              'write local CSV metadata M=200')
   call bench_format_mpi_union_text(REPORT_N_SMALL, REPS_REPORT, 8, count_rate, &
                                    'format sparse union text N=100')
   call bench_format_mpi_union_text(REPORT_N_LARGE, REPS_REPORT_LARGE, 8, count_rate, &
                                    'format sparse union text N=1000')
#ifdef FTIMER_USE_MPI
   call bench_write_strict_mpi_csv(REPORT_N_SMALL, REPS_MPI_REPORT, count_rate)
#endif
#if defined(FTIMER_USE_MPI) && defined(FTIMER_USE_OPENMP)
   call bench_write_strict_mpi_openmp_csv(1, 1, count_rate)
   call bench_write_sparse_mpi_openmp_union_csv(2, 1, count_rate)
#endif

   call write_bench_line('')

   ! --- Date formatting / cache scenarios ---
   call bench_raw_date_string(REPS_DATE_RAW, count_rate)
   call bench_cached_date_string(REPS_DATE_CACHED, count_rate)

   call write_bench_line('')
   call write_bench_line('Notes:')
   call write_bench_line('  - Nesting "per-op" = per full nest cycle (D pushes + D pops).')
   call write_bench_line('  - Context scaling "per-op" = one parent/work start-stop cycle.')
   call write_bench_line('  - First-touch rows exclude timer init/finalize and prebuilt-name formatting.')
   call write_bench_line('  - get_summary "per-op" = per summary build call.')
   call write_bench_line('  - build_summary (direct) uses prebuilt flat segments and fixed dates.')
   call write_bench_line('  - Reporting rows measure generated report size effects without hard thresholds.')
   call write_bench_line('  - strict MPI CSV reporting appears only in FTIMER_USE_MPI=ON builds.')
   call write_bench_line('  - raw date string = uncached date_and_time + formatting.')
   call write_bench_line('  - ftimer_date_string steady-state = cached path after warm-up.')
   call write_bench_line('  - Long-name name-based rows include full per-call validation and hashing of the label.')
   call write_bench_line('  - name-based start/stop remains the default path; lookup/start_id/stop_id is the optional hot path.')
   call write_bench_line('  - ftimer_openmp worker rows appear only in FTIMER_USE_OPENMP=ON builds.')
   call write_bench_line('  - ftimer_openmp lane touch rows time only participating-lane first touch.')
   call write_bench_line('  - All scenarios use the real wall-clock (no mock clock).')
   call write_bench_line('  - Timings include clock-call overhead inside start/stop.')
   call write_bench_line('  - Pass a CSV path as argv[1] to archive parseable benchmark results.')

   call close_bench_csv()
#ifdef FTIMER_USE_MPI
   call MPI_Finalize(mpierr)
#endif

contains

   logical function is_reporting_rank() result(is_root)
      is_root = (bench_rank == 0)
   end function is_reporting_rank

   subroutine setup_bench_csv()
      character(len=:), allocatable :: csv_path
      character(len=256) :: iomsg
      integer :: arg_len
      integer :: arg_status
      integer :: io

      if (.not. is_reporting_rank()) return
      if (command_argument_count() < 1) return

      call get_command_argument(1, length=arg_len, status=arg_status)
      if (arg_status /= 0) then
         write (error_unit, '(a)') 'ftimer_bench: unable to read CSV result path argument'
         error stop
      end if
      if (arg_len <= 0) return
      allocate (character(len=arg_len) :: csv_path)
      call get_command_argument(1, csv_path, status=arg_status)
      if (arg_status /= 0) then
         write (error_unit, '(a)') 'ftimer_bench: unable to read CSV result path argument'
         error stop
      end if
      bench_csv_path = trim(csv_path)

      open (newunit=bench_csv_unit, file=bench_csv_path, status='replace', action='write', &
            iostat=io, iomsg=iomsg)
      if (io /= 0) then
         write (error_unit, '(a)') 'ftimer_bench: unable to write CSV result file: '//trim(iomsg)
         error stop
      end if

      bench_csv_enabled = .true.
      write (bench_csv_unit, '(a)') 'benchmark,reps,total_ms,per_op_ns'
   end subroutine setup_bench_csv

   subroutine setup_report_scratch_paths()
      local_csv_report_path = make_scratch_path('local_report')
      mpi_csv_report_path = make_scratch_path('mpi_report')
   end subroutine setup_report_scratch_paths

   subroutine setup_bench_csv_smoke_only()
      character(len=16) :: value
      integer :: env_status

      call get_environment_variable('FTIMER_BENCH_CSV_SMOKE_ONLY', value, status=env_status)
      if (env_status /= 0) return
      select case (trim(value))
      case ('1', 'ON', 'on', 'TRUE', 'true')
         bench_csv_smoke_only = .true.
      case default
         bench_csv_smoke_only = .false.
      end select
   end subroutine setup_bench_csv_smoke_only

   function make_scratch_path(role) result(path)
      character(len=*), intent(in) :: role
      character(len=:), allocatable :: path
      character(len=512) :: tmpdir
      character(len=32) :: count_text
      character(len=16) :: pid_text
      character(len=16) :: rank_text
      integer(int64) :: count
      integer :: env_status
      integer :: attempt
      logical :: exists

      call get_environment_variable('TMPDIR', tmpdir, status=env_status)
      if (env_status /= 0 .or. len_trim(tmpdir) <= 0) tmpdir = '/tmp'
      call system_clock(count=count)
      write (count_text, '(i0)') count
      write (pid_text, '(i0)') int(c_getpid())
      write (rank_text, '(i0)') bench_rank

      attempt = 0
      do
         path = trim_trailing_slash(trim(tmpdir))//'/ftimer_bench_'//trim(role)//'_'// &
                trim(pid_text)//'_'//trim(count_text)//'_r'//trim(rank_text)// &
                scratch_attempt_suffix(attempt)//'.csv'
         inquire (file=path, exist=exists)
         if ((.not. exists) .and. (.not. path_matches_bench_csv(path))) exit
         attempt = attempt + 1
      end do
   end function make_scratch_path

   function trim_trailing_slash(path) result(trimmed)
      character(len=*), intent(in) :: path
      character(len=:), allocatable :: trimmed
      integer :: last

      trimmed = trim(path)
      do
         last = len(trimmed)
         if (last <= 1) exit
         if (trimmed(last:last) /= '/') exit
         trimmed = trimmed(1:last - 1)
      end do
   end function trim_trailing_slash

   function scratch_attempt_suffix(attempt) result(suffix)
      integer, intent(in) :: attempt
      character(len=:), allocatable :: suffix
      character(len=16) :: attempt_text

      if (attempt <= 0) then
         suffix = ''
      else
         write (attempt_text, '(i0)') attempt
         suffix = '_'//trim(attempt_text)
      end if
   end function scratch_attempt_suffix

   logical function path_matches_bench_csv(path) result(matches)
      character(len=*), intent(in) :: path

      matches = .false.
      if (.not. allocated(bench_csv_path)) return
      matches = trim(path) == trim(bench_csv_path)
   end function path_matches_bench_csv

   subroutine close_bench_csv()
      if (.not. bench_csv_enabled) return
      close (bench_csv_unit)
      bench_csv_enabled = .false.
      bench_csv_unit = -1
   end subroutine close_bench_csv

   subroutine write_bench_line(line)
      character(len=*), intent(in) :: line

      if (.not. is_reporting_rank()) return
      write (*, '(a)') line
   end subroutine write_bench_line

   subroutine write_bench_header()
      if (.not. is_reporting_rank()) return
      write (*, '(a47,a10,a12,a13)') &
         'Benchmark                                      ', &
         '      Reps', '  Total(ms)', '  Per-op(ns)'
      write (*, '(a82)') repeat('-', 82)
   end subroutine write_bench_header

   subroutine write_csv_result(label, reps, total_ms, per_op_ns)
      character(len=*), intent(in) :: label
      integer, intent(in) :: reps
      real(real64), intent(in) :: total_ms
      real(real64), intent(in) :: per_op_ns

      if (.not. bench_csv_enabled) return
      write (bench_csv_unit, '(a,",",i0,",",f0.6,",",f0.3)') &
         csv_quote(trim(label)), reps, total_ms, per_op_ns
   end subroutine write_csv_result

   function csv_quote(value) result(field)
      character(len=*), intent(in) :: value
      character(len=:), allocatable :: field
      integer :: i

      field = '"'
      do i = 1, len_trim(value)
         if (value(i:i) == '"') then
            field = field//'""'
         else
            field = field//value(i:i)
         end if
      end do
      field = field//'"'
   end function csv_quote

   subroutine consume_report_text(text)
      character(len=*), intent(in) :: text

      text_sink = text_sink + int(len(text), int64)
   end subroutine consume_report_text

   subroutine delete_file_if_present(filename)
      character(len=*), intent(in) :: filename
      integer :: file_unit
      integer :: io

      open (newunit=file_unit, file=filename, status='old', action='write', iostat=io)
      if (io == 0) close (file_unit, status='delete')
   end subroutine delete_file_if_present

   subroutine require_success(ierr, operation)
      integer, intent(in) :: ierr
      character(len=*), intent(in) :: operation

      if (ierr == 0) return
      write (error_unit, '(a,i0)') 'ftimer_bench: '//trim(operation)//' failed with ierr=', ierr
      error stop
   end subroutine require_success

   ! Name-based start/stop, single timer, steady-state loop.
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

   ! Id-based start/stop, pre-registered timer.
   ! No name normalization, no segment lookup. Isolates pure stack push/pop
   ! and clock-call cost from the mapped-lookup cost in name-based start/stop.
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

   subroutine bench_openmp_serial_lane_id(reps, count_rate)
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer :: i, id, ierr
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer

      config%max_lanes = 1
      call timer%init(config=config, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp serial init')
      call timer%register_timer('t', id, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp serial register_timer')

      call timer%start_id(id, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp serial warm start_id')
      call timer%stop_id(id, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp serial warm stop_id')

      call system_clock(t0)
      do i = 1, reps
         call timer%start_id(id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 'ftimer_bench: ftimer_openmp serial start_id failed'
         call timer%stop_id(id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 'ftimer_bench: ftimer_openmp serial stop_id failed'
      end do
      call system_clock(t1)

      call timer%finalize(ierr=ierr)
      call require_success(ierr, 'ftimer_openmp serial finalize')
      call print_result('ftimer_openmp serial lane (id-based)', reps, t0, t1, count_rate)
   end subroutine bench_openmp_serial_lane_id

#ifdef FTIMER_USE_OPENMP
   subroutine bench_openmp_region_open_close(reps, count_rate)
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer :: i, ierr
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer

      config%max_lanes = 3
      call timer%init(config=config, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp region init')

      call system_clock(t0)
      do i = 1, reps
         call timer%begin_parallel_region(region, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 'ftimer_bench: ftimer_openmp begin_parallel_region failed'
         call timer%end_parallel_region(region, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 'ftimer_bench: ftimer_openmp end_parallel_region failed'
      end do
      call system_clock(t1)

      call timer%finalize(ierr=ierr)
      call require_success(ierr, 'ftimer_openmp region finalize')
      call print_result('ftimer_openmp region open/close', reps, t0, t1, count_rate)
   end subroutine bench_openmp_region_open_close

   subroutine bench_openmp_worker_lane_id(reps, count_rate)
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer :: bad, i, id, ierr, worker_seen
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer

      call omp_set_dynamic(.false.)
      config%max_lanes = 3
      call timer%init(config=config, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker init')
      call timer%register_timer('worker', id, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker register_timer')
      call timer%begin_parallel_region(region, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker begin_parallel_region')

      bad = 0
      worker_seen = 0
      t0 = 0_int64
      t1 = 0_int64

!$omp parallel num_threads(2) default(shared) private(ierr, i) reduction(+:bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         call timer%start_id(id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) bad = bad + 1
         call timer%stop_id(id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) bad = bad + 1
      end if
!$omp barrier
      if (omp_get_thread_num() == 1) then
         call system_clock(t0)
         do i = 1, reps
            call timer%start_id(id, ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
            call timer%stop_id(id, ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
         end do
         call system_clock(t1)
      end if
!$omp end parallel

      if (bad /= 0) error stop 'ftimer_bench: ftimer_openmp worker start/stop failed'
      if (worker_seen <= 0) then
         call timer%end_parallel_region(region, ierr=ierr)
         call require_success(ierr, 'ftimer_openmp worker skipped end_parallel_region')
         call timer%finalize(ierr=ierr)
         call require_success(ierr, 'ftimer_openmp worker skipped finalize')
         call write_bench_line('ftimer_openmp worker lane (id-based) skipped: OpenMP did not provide thread 1')
         return
      end if
      call timer%end_parallel_region(region, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker end_parallel_region')
      call timer%finalize(ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker finalize')
      call print_result('ftimer_openmp worker lane (id-based)', reps, t0, t1, count_rate)
   end subroutine bench_openmp_worker_lane_id

   subroutine bench_openmp_worker_context_scaling(reps_outer, num_contexts, count_rate)
      integer, intent(in) :: reps_outer
      integer, intent(in) :: num_contexts
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer, allocatable :: parent_ids(:)
      integer :: bad, i, ierr, j, total_ops, worker_seen, work_id
      character(len=8) :: parent_name
      character(len=47) :: label
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer

      total_ops = reps_outer*num_contexts
      allocate (parent_ids(num_contexts))

      call omp_set_dynamic(.false.)
      config%max_lanes = 3
      call timer%init(config=config, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker context init')
      do j = 1, num_contexts
         write (parent_name, '("p",i7.7)') j
         call timer%register_timer(parent_name, parent_ids(j), ierr=ierr)
         call require_success(ierr, 'ftimer_openmp worker context register parent')
      end do
      call timer%register_timer('work', work_id, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker context register work')
      call timer%begin_parallel_region(region, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker context begin_parallel_region')

      bad = 0
      worker_seen = 0
      t0 = 0_int64
      t1 = 0_int64

!$omp parallel num_threads(2) default(shared) private(ierr, i, j) reduction(+:bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         do j = 1, num_contexts
            call timer%start_id(parent_ids(j), ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
            call timer%start_id(work_id, ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
            call timer%stop_id(work_id, ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
            call timer%stop_id(parent_ids(j), ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
         end do
      end if
!$omp barrier
      if (omp_get_thread_num() == 1) then
         call system_clock(t0)
         do i = 1, reps_outer
            do j = 1, num_contexts
               call timer%start_id(parent_ids(j), ierr=ierr)
               if (ierr /= FTIMER_SUCCESS) bad = bad + 1
               call timer%start_id(work_id, ierr=ierr)
               if (ierr /= FTIMER_SUCCESS) bad = bad + 1
               call timer%stop_id(work_id, ierr=ierr)
               if (ierr /= FTIMER_SUCCESS) bad = bad + 1
               call timer%stop_id(parent_ids(j), ierr=ierr)
               if (ierr /= FTIMER_SUCCESS) bad = bad + 1
            end do
         end do
         call system_clock(t1)
      end if
!$omp end parallel

      if (bad /= 0) error stop 'ftimer_bench: ftimer_openmp worker context scaling failed'
      if (worker_seen <= 0) then
         call timer%end_parallel_region(region, ierr=ierr)
         call require_success(ierr, 'ftimer_openmp worker context skipped end_parallel_region')
         call timer%finalize(ierr=ierr)
         call require_success(ierr, 'ftimer_openmp worker context skipped finalize')
         call write_bench_line('ftimer_openmp worker context scaling skipped: OpenMP did not provide thread 1')
         deallocate (parent_ids)
         return
      end if

      call timer%end_parallel_region(region, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker context end_parallel_region')
      call timer%finalize(ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker context finalize')
      deallocate (parent_ids)
      write (label, '("ftimer_openmp worker ctx C=",i0)') num_contexts
      call print_result(trim(label), total_ops, t0, t1, count_rate)
   end subroutine bench_openmp_worker_context_scaling

   subroutine bench_openmp_catalog_register(reps_outer, num_timers, count_rate)
      integer, intent(in) :: reps_outer
      integer, intent(in) :: num_timers
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      character(len=8), allocatable :: tnames(:)
      character(len=47) :: label
      integer :: i, id, ierr, j, total_ops
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t), allocatable :: timers(:)

      total_ops = reps_outer*num_timers
      allocate (tnames(num_timers))
      allocate (timers(reps_outer))
      config%max_lanes = 1
      do j = 1, num_timers
         write (tnames(j), '("t",i7.7)') j
      end do
      do i = 1, reps_outer
         call timers(i)%init(config=config, ierr=ierr)
         call require_success(ierr, 'ftimer_openmp catalog register init')
      end do

      call system_clock(t0)
      do i = 1, reps_outer
         do j = 1, num_timers
            call timers(i)%register_timer(tnames(j), id, ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) error stop 'ftimer_bench: ftimer_openmp register_timer failed'
         end do
      end do
      call system_clock(t1)

      do i = 1, reps_outer
         call timers(i)%finalize(ierr=ierr)
         call require_success(ierr, 'ftimer_openmp catalog register finalize')
      end do
      deallocate (timers)
      deallocate (tnames)
      write (label, '("ftimer_openmp catalog register N=",i0)') num_timers
      call print_result(trim(label), total_ops, t0, t1, count_rate)
   end subroutine bench_openmp_catalog_register

   subroutine bench_openmp_catalog_lookup(reps_outer, num_timers, count_rate)
      integer, intent(in) :: reps_outer
      integer, intent(in) :: num_timers
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      character(len=8), allocatable :: tnames(:)
      character(len=47) :: label
      integer :: i, id, ierr, j, total_ops
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer

      total_ops = reps_outer*num_timers
      allocate (tnames(num_timers))
      config%max_lanes = 1
      call timer%init(config=config, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp catalog lookup init')
      do j = 1, num_timers
         write (tnames(j), '("t",i7.7)') j
         call timer%register_timer(tnames(j), id, ierr=ierr)
         call require_success(ierr, 'ftimer_openmp catalog lookup register')
      end do

      call system_clock(t0)
      do i = 1, reps_outer
         do j = 1, num_timers
            call timer%lookup_timer(tnames(j), id, ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) error stop 'ftimer_bench: ftimer_openmp lookup_timer failed'
         end do
      end do
      call system_clock(t1)

      call timer%finalize(ierr=ierr)
      call require_success(ierr, 'ftimer_openmp catalog lookup finalize')
      deallocate (tnames)
      write (label, '("ftimer_openmp catalog lookup N=",i0)') num_timers
      call print_result(trim(label), total_ops, t0, t1, count_rate)
   end subroutine bench_openmp_catalog_lookup

   subroutine bench_openmp_worker_lanes(reps, num_lanes, count_rate)
      integer, intent(in) :: reps
      integer, intent(in) :: num_lanes
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      character(len=47) :: label
      integer :: bad, i, id, ierr, total_ops, worker_seen
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer

      total_ops = reps*num_lanes
      call omp_set_dynamic(.false.)
      config%max_lanes = num_lanes + 1
      call timer%init(config=config, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker lanes init')
      call timer%register_timer('worker', id, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker lanes register_timer')
      call timer%begin_parallel_region(region, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker lanes begin_parallel_region')

      bad = 0
      worker_seen = 0
      t0 = 0_int64
      t1 = 0_int64

!$omp parallel num_threads(num_lanes) default(shared) private(ierr, i) reduction(+:bad, worker_seen)
      worker_seen = worker_seen + 1
      call timer%start_id(id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) bad = bad + 1
      call timer%stop_id(id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) bad = bad + 1
!$omp barrier
!$omp master
      call system_clock(t0)
!$omp end master
!$omp barrier
      do i = 1, reps
         call timer%start_id(id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) bad = bad + 1
         call timer%stop_id(id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) bad = bad + 1
      end do
!$omp barrier
!$omp master
      call system_clock(t1)
!$omp end master
!$omp end parallel

      if (bad /= 0) error stop 'ftimer_bench: ftimer_openmp worker lanes failed'
      if (worker_seen < num_lanes) then
         call timer%end_parallel_region(region, ierr=ierr)
         call require_success(ierr, 'ftimer_openmp worker lanes skipped end_parallel_region')
         call timer%finalize(ierr=ierr)
         call require_success(ierr, 'ftimer_openmp worker lanes skipped finalize')
         write (label, '("ftimer_openmp worker lanes L=",i0," skipped")') num_lanes
         call write_bench_line(trim(label))
         return
      end if

      call timer%end_parallel_region(region, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker lanes end_parallel_region')
      call timer%finalize(ierr=ierr)
      call require_success(ierr, 'ftimer_openmp worker lanes finalize')
      write (label, '("ftimer_openmp worker lanes L=",i0)') num_lanes
      call print_result(trim(label), total_ops, t0, t1, count_rate)
   end subroutine bench_openmp_worker_lanes

   subroutine bench_openmp_worker_lanes_split(reps, num_lanes, count_rate)
      integer, intent(in) :: reps
      integer, intent(in) :: num_lanes
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      character(len=47) :: label
      integer, allocatable :: ids(:)
      integer :: bad, i, ierr, lane, total_ops, worker_seen
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t), allocatable :: regions(:)
      type(ftimer_openmp_t), allocatable :: timers(:)

      total_ops = reps*num_lanes
      allocate (ids(num_lanes))
      allocate (regions(num_lanes))
      allocate (timers(num_lanes))

      call omp_set_dynamic(.false.)
      config%max_lanes = num_lanes + 1
      do lane = 1, num_lanes
         call timers(lane)%init(config=config, ierr=ierr)
         call require_success(ierr, 'ftimer_openmp worker split init')
         call timers(lane)%register_timer('worker', ids(lane), ierr=ierr)
         call require_success(ierr, 'ftimer_openmp worker split register_timer')
         call timers(lane)%begin_parallel_region(regions(lane), ierr=ierr)
         call require_success(ierr, 'ftimer_openmp worker split begin_parallel_region')
      end do

      bad = 0
      worker_seen = 0
      t0 = 0_int64
      t1 = 0_int64

!$omp parallel num_threads(num_lanes) default(shared) private(ierr, i, lane) reduction(+:bad, worker_seen)
      lane = omp_get_thread_num() + 1
      worker_seen = worker_seen + 1
      call timers(lane)%start_id(ids(lane), ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) bad = bad + 1
      call timers(lane)%stop_id(ids(lane), ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) bad = bad + 1
!$omp barrier
!$omp master
      call system_clock(t0)
!$omp end master
!$omp barrier
      do i = 1, reps
         call timers(lane)%start_id(ids(lane), ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) bad = bad + 1
         call timers(lane)%stop_id(ids(lane), ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) bad = bad + 1
      end do
!$omp barrier
!$omp master
      call system_clock(t1)
!$omp end master
!$omp end parallel

      if (bad /= 0) error stop 'ftimer_bench: ftimer_openmp worker split lanes failed'
      if (worker_seen < num_lanes) then
         do lane = 1, num_lanes
            call timers(lane)%end_parallel_region(regions(lane), ierr=ierr)
            call require_success(ierr, 'ftimer_openmp worker split skipped end_parallel_region')
            call timers(lane)%finalize(ierr=ierr)
            call require_success(ierr, 'ftimer_openmp worker split skipped finalize')
         end do
         write (label, '("ftimer_openmp worker split L=",i0," skipped")') num_lanes
         call write_bench_line(trim(label))
         deallocate (timers)
         deallocate (regions)
         deallocate (ids)
         return
      end if

      do lane = 1, num_lanes
         call timers(lane)%end_parallel_region(regions(lane), ierr=ierr)
         call require_success(ierr, 'ftimer_openmp worker split end_parallel_region')
         call timers(lane)%finalize(ierr=ierr)
         call require_success(ierr, 'ftimer_openmp worker split finalize')
      end do
      deallocate (timers)
      deallocate (regions)
      deallocate (ids)
      write (label, '("ftimer_openmp worker split L=",i0)') num_lanes
      call print_result(trim(label), total_ops, t0, t1, count_rate)
   end subroutine bench_openmp_worker_lanes_split

   subroutine bench_openmp_lane_first_touch(configured_lanes, num_timers, count_rate)
      integer, intent(in) :: configured_lanes
      integer, intent(in) :: num_timers
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      character(len=8) :: tname
      character(len=47) :: label
      integer, allocatable :: ids(:)
      integer :: bad, ierr, j, worker_seen
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer

      allocate (ids(num_timers))
      call omp_set_dynamic(.false.)
      config%max_lanes = configured_lanes
      call timer%init(config=config, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp lane touch init')
      do j = 1, num_timers
         write (tname, '("t",i7.7)') j
         call timer%register_timer(tname, ids(j), ierr=ierr)
         call require_success(ierr, 'ftimer_openmp lane touch register_timer')
      end do
      call timer%begin_parallel_region(region, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp lane touch begin_parallel_region')

      bad = 0
      worker_seen = 0
      t0 = 0_int64
      t1 = 0_int64

!$omp parallel num_threads(2) default(shared) private(ierr, j) reduction(+:bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         call system_clock(t0)
         do j = 1, num_timers
            call timer%start_id(ids(j), ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
            call timer%stop_id(ids(j), ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
         end do
         call system_clock(t1)
      end if
!$omp end parallel

      if (bad /= 0) error stop 'ftimer_bench: ftimer_openmp lane first touch failed'
      if (worker_seen <= 0) then
         call timer%end_parallel_region(region, ierr=ierr)
         call require_success(ierr, 'ftimer_openmp lane touch skipped end_parallel_region')
         call timer%finalize(ierr=ierr)
         call require_success(ierr, 'ftimer_openmp lane touch skipped finalize')
         call write_bench_line('ftimer_openmp lane first-touch skipped: OpenMP did not provide thread 1')
         deallocate (ids)
         return
      end if

      call timer%end_parallel_region(region, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp lane touch end_parallel_region')
      call timer%finalize(ierr=ierr)
      call require_success(ierr, 'ftimer_openmp lane touch finalize')
      deallocate (ids)
      write (label, '("ftimer_openmp lane touch K=",i0," N=",i0)') configured_lanes, num_timers
      call print_result(trim(label), num_timers, t0, t1, count_rate)
   end subroutine bench_openmp_lane_first_touch
#endif

   ! Long-name start/stop with one steady-state resident timer.
   ! The name-based rows include per-call validation and hashing across the full
   ! label length. The id-based row shows the cached-id path after one lookup.
   subroutine bench_long_name(reps, name_len, use_id, count_rate)
      integer, intent(in) :: reps
      integer, intent(in) :: name_len
      logical, intent(in) :: use_id
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      character(len=:), allocatable :: tname
      character(len=47) :: label
      integer :: i, id

      tname = repeat('l', name_len)

      call ftimer_init()
      id = ftimer_lookup(tname)
      call system_clock(t0)
      if (use_id) then
         do i = 1, reps
            call ftimer_start_id(id)
            call ftimer_stop_id(id)
         end do
      else
         do i = 1, reps
            call ftimer_start(tname)
            call ftimer_stop(tname)
         end do
      end if
      call system_clock(t1)
      call ftimer_finalize()

      if (use_id) then
         write (label, '("long name L=",i0," (id-based)")') name_len
      else
         write (label, '("long name L=",i0," (name-based)")') name_len
      end if
      call print_result(trim(label), reps, t0, t1, count_rate)
   end subroutine bench_long_name

   ! Name-based lookup with N unique timers.
   ! Cycles through all N timers each outer rep. Each inner start/stop uses
   ! the same public name-based path as production code, but with a large
   ! resident timer set already registered. The 1/10/50 points preserve the
   ! original benchmark comparison set, while 100/1000 extend the view into
   ! larger timer populations. Together they show whether the internal name
   ! map keeps steady-state lookup near-flat as N grows.
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

   ! New timer discovery through lookup. This measures the
   ! internal segment array, name-index, and name storage allocation/growth cost
   ! that remains on the first touch of a previously unseen timer name. The
   ! repetitions use independent already-initialized timer objects inside one
   ! timed window so small rows are not dominated by system_clock call noise.
   subroutine bench_timer_first_touch(reps_outer, num_timers, count_rate)
      integer, intent(in) :: reps_outer
      integer, intent(in) :: num_timers
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer :: i, id, j, total_ops
      character(len=8), allocatable :: tnames(:)
      character(len=47) :: label
      type(ftimer_t), allocatable :: timers(:)

      total_ops = reps_outer*num_timers
      allocate (tnames(num_timers))
      allocate (timers(reps_outer))
      do j = 1, num_timers
         write (tnames(j), '("t",i7.7)') j
      end do

      do i = 1, reps_outer
         call timers(i)%init()
      end do

      call system_clock(t0)
      do i = 1, reps_outer
         do j = 1, num_timers
            id = timers(i)%lookup(tnames(j))
         end do
      end do
      call system_clock(t1)

      do i = 1, reps_outer
         call timers(i)%finalize()
      end do

      deallocate (timers)
      deallocate (tnames)
      write (label, '("timer first-touch N=",i0," (lookup)")') num_timers
      call print_result(trim(label), total_ops, t0, t1, count_rate)
   end subroutine bench_timer_first_touch

   ! New context creation for one already-known hot timer.
   ! Parent timers and their root contexts are warmed before the measured block,
   ! so the measured work isolates first creation of the work timer's distinct
   ! parent-stack contexts plus the steady parent/work start-stop cycle. The
   ! repetitions use independent already-initialized timer objects inside one
   ! timed window so small rows are not dominated by system_clock call noise.
   subroutine bench_context_first_touch(reps_outer, num_contexts, count_rate)
      integer, intent(in) :: reps_outer
      integer, intent(in) :: num_contexts
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer, allocatable :: parent_ids(:)
      type(ftimer_t), allocatable :: timers(:)
      integer :: i, j, total_ops, work_id
      character(len=8) :: parent_name
      character(len=47) :: label

      total_ops = reps_outer*num_contexts
      allocate (parent_ids(num_contexts))
      allocate (timers(reps_outer))

      do i = 1, reps_outer
         call timers(i)%init()
         do j = 1, num_contexts
            write (parent_name, '("p",i7.7)') j
            parent_ids(j) = timers(i)%lookup(parent_name)
         end do
         work_id = timers(i)%lookup('work')

         do j = 1, num_contexts
            call timers(i)%start_id(parent_ids(j))
            call timers(i)%stop_id(parent_ids(j))
         end do
      end do

      call system_clock(t0)
      do i = 1, reps_outer
         do j = 1, num_contexts
            call timers(i)%start_id(parent_ids(j))
            call timers(i)%start_id(work_id)
            call timers(i)%stop_id(work_id)
            call timers(i)%stop_id(parent_ids(j))
         end do
      end do
      call system_clock(t1)

      do i = 1, reps_outer
         call timers(i)%finalize()
      end do

      deallocate (timers)
      deallocate (parent_ids)
      write (label, '("context first-touch C=",i0," (id-based)")') num_contexts
      call print_result(trim(label), total_ops, t0, t1, count_rate)
   end subroutine bench_context_first_touch

   ! One timer reused under many parent stacks.
   ! Each cycle times the same "work" timer under a distinct parent, so the
   ! hot path sees growing context counts for one segment. The name-based rows
   ! keep the default public API path; the id-based rows isolate the
   ! parent-stack lookup cost from name normalization and timer-name lookup.
   subroutine bench_context_scaling_name(reps_outer, num_contexts, count_rate)
      integer, intent(in) :: reps_outer
      integer, intent(in) :: num_contexts
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer :: i, j, total_ops
      character(len=8), allocatable :: parent_names(:)
      character(len=47) :: label

      total_ops = reps_outer*num_contexts
      allocate (parent_names(num_contexts))
      call ftimer_init()
      do j = 1, num_contexts
         write (parent_names(j), '("p",i7.7)') j
         i = ftimer_lookup(parent_names(j))
      end do
      i = ftimer_lookup('work')

      do j = 1, num_contexts
         call ftimer_start(parent_names(j))
         call ftimer_start('work')
         call ftimer_stop('work')
         call ftimer_stop(parent_names(j))
      end do

      call system_clock(t0)
      do i = 1, reps_outer
         do j = 1, num_contexts
            call ftimer_start(parent_names(j))
            call ftimer_start('work')
            call ftimer_stop('work')
            call ftimer_stop(parent_names(j))
         end do
      end do
      call system_clock(t1)
      call ftimer_finalize()
      deallocate (parent_names)
      write (label, '("context scaling C=",i0," (name-based)")') num_contexts
      call print_result(trim(label), total_ops, t0, t1, count_rate)
   end subroutine bench_context_scaling_name

   subroutine bench_context_scaling_id(reps_outer, num_contexts, count_rate)
      integer, intent(in) :: reps_outer
      integer, intent(in) :: num_contexts
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0, t1
      integer, allocatable :: parent_ids(:)
      integer :: i, j, total_ops, work_id
      character(len=8) :: parent_name
      character(len=47) :: label

      total_ops = reps_outer*num_contexts
      allocate (parent_ids(num_contexts))
      call ftimer_init()
      do j = 1, num_contexts
         write (parent_name, '("p",i7.7)') j
         parent_ids(j) = ftimer_lookup(parent_name)
      end do
      work_id = ftimer_lookup('work')

      do j = 1, num_contexts
         call ftimer_start_id(parent_ids(j))
         call ftimer_start_id(work_id)
         call ftimer_stop_id(work_id)
         call ftimer_stop_id(parent_ids(j))
      end do

      call system_clock(t0)
      do i = 1, reps_outer
         do j = 1, num_contexts
            call ftimer_start_id(parent_ids(j))
            call ftimer_start_id(work_id)
            call ftimer_stop_id(work_id)
            call ftimer_stop_id(parent_ids(j))
         end do
      end do
      call system_clock(t1)
      call ftimer_finalize()
      deallocate (parent_ids)
      write (label, '("context scaling C=",i0," (id-based)")') num_contexts
      call print_result(trim(label), total_ops, t0, t1, count_rate)
   end subroutine bench_context_scaling_id

   ! Id-based nesting at increasing depths.
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

   ! get_summary overhead with N flat timers.
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

#ifdef FTIMER_USE_OPENMP
   subroutine bench_openmp_summary_merge(num_timers, reps, count_rate)
      integer, intent(in) :: num_timers
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0
      integer(int64) :: t1
      integer :: ierr
      integer :: i
      type(ftimer_openmp_summary_t) :: summary
      type(ftimer_openmp_t) :: timer

      call prepare_openmp_timer_with_flat_entries(timer, num_timers, .false.)

      call system_clock(t0)
      do i = 1, reps
         call timer%get_openmp_summary(summary, ierr=ierr)
         call require_success(ierr, 'get_openmp_summary')
         text_sink = text_sink + int(summary%num_entries, int64)
      end do
      call system_clock(t1)

      call timer%finalize(ierr=ierr)
      call require_success(ierr, 'ftimer_openmp summary finalize')
      call print_result('ftimer_openmp summary merge N=100 entries', reps, t0, t1, count_rate)
   end subroutine bench_openmp_summary_merge
#endif

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

   subroutine bench_format_local_text(num_timers, reps, name_len, metadata_count, count_rate, label)
      integer, intent(in) :: num_timers
      integer, intent(in) :: reps
      integer, intent(in) :: name_len
      integer, intent(in) :: metadata_count
      integer(int64), intent(in) :: count_rate
      character(len=*), intent(in) :: label
      integer(int64) :: t0
      integer(int64) :: t1
      integer :: i
      type(ftimer_metadata_t), allocatable :: metadata(:)
      type(ftimer_segment_t), allocatable :: segments(:)
      type(ftimer_summary_t) :: summary
      character(len=:), allocatable :: text

      if (.not. is_reporting_rank()) return

      call build_flat_segments(segments, num_timers, name_len)
      call build_summary(summary=summary, segments=segments, init_wtime=0.0_wp, init_date=BENCH_DATE, &
                         end_time=real(num_timers, wp), end_date=BENCH_DATE)
      if (metadata_count > 0) call build_metadata(metadata, metadata_count)

      call system_clock(t0)
      do i = 1, reps
         if (metadata_count > 0) then
            call format_summary(summary, text, metadata)
         else
            call format_summary(summary, text)
         end if
         call consume_report_text(text)
      end do
      call system_clock(t1)

      if (allocated(metadata)) deallocate (metadata)
      if (allocated(segments)) deallocate (segments)
      call print_result(label, reps, t0, t1, count_rate)
   end subroutine bench_format_local_text

   subroutine bench_write_local_csv(num_timers, reps, name_len, metadata_count, count_rate, label)
      integer, intent(in) :: num_timers
      integer, intent(in) :: reps
      integer, intent(in) :: name_len
      integer, intent(in) :: metadata_count
      integer(int64), intent(in) :: count_rate
      character(len=*), intent(in) :: label
      integer(int64) :: t0
      integer(int64) :: t1
      integer :: ierr
      integer :: i
      type(ftimer_metadata_t), allocatable :: metadata(:)
      type(ftimer_t) :: timer

      if (.not. is_reporting_rank()) return

      call prepare_timer_with_flat_entries(timer, num_timers, name_len)
      if (metadata_count > 0) call build_metadata(metadata, metadata_count)
      call delete_file_if_present(LOCAL_CSV_REPORT_PATH)

      call system_clock(t0)
      do i = 1, reps
         if (metadata_count > 0) then
            call timer%write_summary_csv(LOCAL_CSV_REPORT_PATH, append=.false., metadata=metadata, ierr=ierr)
         else
            call timer%write_summary_csv(LOCAL_CSV_REPORT_PATH, append=.false., ierr=ierr)
         end if
         call require_success(ierr, 'write_summary_csv')
      end do
      call system_clock(t1)

      call timer%finalize()
      if (allocated(metadata)) deallocate (metadata)
      call delete_file_if_present(LOCAL_CSV_REPORT_PATH)
      call print_result(label, reps, t0, t1, count_rate)
   end subroutine bench_write_local_csv

   subroutine bench_format_mpi_union_text(num_timers, reps, name_len, count_rate, label)
      integer, intent(in) :: num_timers
      integer, intent(in) :: reps
      integer, intent(in) :: name_len
      integer(int64), intent(in) :: count_rate
      character(len=*), intent(in) :: label
      integer(int64) :: t0
      integer(int64) :: t1
      integer :: i
      type(ftimer_mpi_union_summary_t) :: summary
      character(len=:), allocatable :: text

      if (.not. is_reporting_rank()) return

      call build_mpi_union_summary_fixture(summary, num_timers, name_len)

      call system_clock(t0)
      do i = 1, reps
         call format_mpi_union_summary(summary, text)
         call consume_report_text(text)
      end do
      call system_clock(t1)

      call print_result(label, reps, t0, t1, count_rate)
   end subroutine bench_format_mpi_union_text

#ifdef FTIMER_USE_MPI
   subroutine bench_write_strict_mpi_csv(num_timers, reps, count_rate)
      integer, intent(in) :: num_timers
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0
      integer(int64) :: t1
      integer :: ierr
      integer :: i
      type(ftimer_t) :: timer

      call prepare_mpi_timer_with_flat_entries(timer, num_timers)
      if (is_reporting_rank()) call delete_file_if_present(MPI_CSV_REPORT_PATH)
      call MPI_Barrier(MPI_COMM_WORLD, mpierr)

      call system_clock(t0)
      do i = 1, reps
         call timer%write_mpi_summary_csv(MPI_CSV_REPORT_PATH, append=.false., ierr=ierr)
         call require_success(ierr, 'write_mpi_summary_csv')
      end do
      call system_clock(t1)

      call MPI_Barrier(MPI_COMM_WORLD, mpierr)
      call timer%finalize()
      if (is_reporting_rank()) call delete_file_if_present(MPI_CSV_REPORT_PATH)
      call print_result('write strict MPI CSV N=100 entries', reps, t0, t1, count_rate)
   end subroutine bench_write_strict_mpi_csv
#endif

#if defined(FTIMER_USE_MPI) && defined(FTIMER_USE_OPENMP)
   subroutine bench_write_strict_mpi_openmp_csv(num_timers, reps, count_rate)
      integer, intent(in) :: num_timers
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0
      integer(int64) :: t1
      integer :: ierr
      integer :: i
      character(len=64) :: label
      type(ftimer_openmp_t) :: timer

      call prepare_openmp_timer_with_flat_entries(timer, num_timers, sparse=.false.)
      if (is_reporting_rank()) call delete_file_if_present(MPI_CSV_REPORT_PATH)
      call MPI_Barrier(MPI_COMM_WORLD, mpierr)

      call system_clock(t0)
      do i = 1, reps
         call timer%write_mpi_openmp_summary_csv(MPI_CSV_REPORT_PATH, append=.false., ierr=ierr)
         call require_success(ierr, 'write_mpi_openmp_summary_csv')
      end do
      call system_clock(t1)

      call MPI_Barrier(MPI_COMM_WORLD, mpierr)
      call timer%finalize(ierr=ierr)
      call require_success(ierr, 'ftimer_openmp strict MPI+OpenMP finalize')
      if (is_reporting_rank()) call delete_file_if_present(MPI_CSV_REPORT_PATH)
      write (label, '("write strict MPI+OpenMP CSV N=",i0," entries")') num_timers
      call print_result(trim(label), reps, t0, t1, count_rate)
   end subroutine bench_write_strict_mpi_openmp_csv

   subroutine bench_write_sparse_mpi_openmp_union_csv(num_timers, reps, count_rate)
      integer, intent(in) :: num_timers
      integer, intent(in) :: reps
      integer(int64), intent(in) :: count_rate
      integer(int64) :: t0
      integer(int64) :: t1
      integer :: ierr
      integer :: i
      character(len=70) :: label
      type(ftimer_openmp_t) :: timer

      call prepare_openmp_timer_with_flat_entries(timer, num_timers, sparse=.true.)
      if (is_reporting_rank()) call delete_file_if_present(MPI_CSV_REPORT_PATH)
      call MPI_Barrier(MPI_COMM_WORLD, mpierr)

      call system_clock(t0)
      do i = 1, reps
         call timer%write_mpi_openmp_union_summary_csv(MPI_CSV_REPORT_PATH, append=.false., ierr=ierr)
         call require_success(ierr, 'write_mpi_openmp_union_summary_csv')
      end do
      call system_clock(t1)

      call MPI_Barrier(MPI_COMM_WORLD, mpierr)
      call timer%finalize(ierr=ierr)
      call require_success(ierr, 'ftimer_openmp sparse MPI+OpenMP finalize')
      if (bench_csv_smoke_only .and. is_reporting_rank()) call require_sparse_union_csv_smoke(MPI_CSV_REPORT_PATH)
      if (is_reporting_rank()) call delete_file_if_present(MPI_CSV_REPORT_PATH)
      write (label, '("write sparse MPI+OpenMP union CSV N=",i0," entries")') num_timers
      call print_result(trim(label), reps, t0, t1, count_rate)
   end subroutine bench_write_sparse_mpi_openmp_union_csv
#endif

   subroutine require_sparse_union_csv_smoke(filename)
      character(len=*), intent(in) :: filename
      character(len=4096) :: line
      character(len=256) :: iomsg
      integer :: file_unit
      integer :: io
      logical :: saw_sparse_policy
      logical :: saw_missing_rank

      saw_sparse_policy = .false.
      saw_missing_rank = .false.
      open (newunit=file_unit, file=filename, status='old', action='read', iostat=io, iomsg=iomsg)
      if (io /= 0) then
         write (error_unit, '(a)') 'ftimer_bench: unable to read sparse union CSV smoke file: '//trim(iomsg)
         error stop
      end if

      do
         read (file_unit, '(a)', iostat=io, iomsg=iomsg) line
         if (io /= 0) exit
         if (index(line, 'sparse_union') > 0) saw_sparse_policy = .true.
         if (index(line, '"entry"') > 0 .and. index(line, '"ttttttt2"') > 0 .and. &
             index(line, '"1","1"') > 0) saw_missing_rank = .true.
      end do
      close (file_unit)

      if (.not. saw_sparse_policy) then
         write (error_unit, '(a)') 'ftimer_bench: sparse union CSV smoke file is missing sparse_union policy'
         error stop
      end if
      if (.not. saw_missing_rank) then
         write (error_unit, '(a)') 'ftimer_bench: sparse union CSV smoke file is missing a sparse entry'
         error stop
      end if
   end subroutine require_sparse_union_csv_smoke

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

   subroutine build_flat_segments(segments, num_timers, name_len)
      type(ftimer_segment_t), allocatable, intent(out) :: segments(:)
      integer, intent(in) :: num_timers
      integer, intent(in), optional :: name_len
      integer :: i
      integer :: actual_name_len
      character(len=:), allocatable :: tname

      actual_name_len = 8
      if (present(name_len)) actual_name_len = name_len

      allocate (segments(num_timers))
      do i = 1, num_timers
         tname = timer_name(i, actual_name_len)
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

   subroutine build_metadata(metadata, count)
      type(ftimer_metadata_t), allocatable, intent(out) :: metadata(:)
      integer, intent(in) :: count
      character(len=16) :: idx_text
      integer :: i

      allocate (metadata(count))
      do i = 1, count
         write (idx_text, '(i0)') i
         metadata(i)%key = 'metadata_key_'//trim(idx_text)
         metadata(i)%value = repeat('value-', 12)//'quoted "'//trim(idx_text)//'", comma field'
      end do
   end subroutine build_metadata

   subroutine prepare_timer_with_flat_entries(timer, num_timers, name_len)
      type(ftimer_t), intent(inout) :: timer
      integer, intent(in) :: num_timers
      integer, intent(in) :: name_len
      character(len=:), allocatable :: tname
      integer :: i

      call timer%init()
      do i = 1, num_timers
         tname = timer_name(i, name_len)
         call timer%start(tname)
         call timer%stop(tname)
      end do
   end subroutine prepare_timer_with_flat_entries

#ifdef FTIMER_USE_MPI
   subroutine prepare_mpi_timer_with_flat_entries(timer, num_timers)
      type(ftimer_t), intent(inout) :: timer
      integer, intent(in) :: num_timers
      character(len=:), allocatable :: tname
      integer :: i

      call timer%init(comm=MPI_COMM_WORLD)
      do i = 1, num_timers
         tname = timer_name(i, 8)
         call timer%start(tname)
         call timer%stop(tname)
      end do
   end subroutine prepare_mpi_timer_with_flat_entries
#endif

#ifdef FTIMER_USE_OPENMP
   subroutine prepare_openmp_timer_with_flat_entries(timer, num_timers, sparse)
      type(ftimer_openmp_t), intent(inout) :: timer
      integer, intent(in) :: num_timers
      logical, intent(in) :: sparse
      integer, allocatable :: ids(:)
      integer :: ierr
      integer :: i
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region

      call omp_set_dynamic(.false.)
      config%max_lanes = 3
#ifdef FTIMER_USE_MPI
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
#else
      call timer%init(config=config, ierr=ierr)
#endif
      call require_success(ierr, 'ftimer_openmp fixture init')

      allocate (ids(num_timers))
      do i = 1, num_timers
         call timer%register_timer(timer_name(i, 8), ids(i), ierr=ierr)
         call require_success(ierr, 'ftimer_openmp fixture register_timer')
      end do

      call timer%begin_parallel_region(region, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp fixture begin_parallel_region')

!$omp parallel num_threads(2) default(shared) private(ierr, i)
      do i = 1, num_timers
         if (sparse) then
            if (modulo(i, 2) == 0 .and. bench_rank /= 0) cycle
            if (modulo(i, 3) == 0 .and. omp_get_thread_num() /= 0) cycle
         end if
         call timer%start_id(ids(i), ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 'ftimer_bench: ftimer_openmp fixture start_id failed'
         call timer%stop_id(ids(i), ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 'ftimer_bench: ftimer_openmp fixture stop_id failed'
      end do
!$omp end parallel

      call timer%end_parallel_region(region, ierr=ierr)
      call require_success(ierr, 'ftimer_openmp fixture end_parallel_region')
      deallocate (ids)
   end subroutine prepare_openmp_timer_with_flat_entries
#endif

   subroutine build_mpi_union_summary_fixture(summary, num_timers, name_len)
      type(ftimer_mpi_union_summary_t), intent(out) :: summary
      integer, intent(in) :: num_timers
      integer, intent(in) :: name_len
      integer :: i
      integer :: participating_ranks

      summary%num_ranks = max(bench_nprocs, 4)
      summary%num_entries = num_timers
      summary%min_total_time = real(num_timers, wp)
      summary%avg_total_time = real(num_timers, wp) + 0.5_wp
      summary%max_total_time = real(num_timers, wp) + 1.0_wp
      summary%total_time_imbalance = 1.0_wp/real(max(num_timers, 1), wp)
      summary%min_total_time_rank = 0
      summary%max_total_time_rank = summary%num_ranks - 1
      allocate (summary%entries(num_timers))

      do i = 1, num_timers
         participating_ranks = 1 + modulo(i - 1, summary%num_ranks)
         summary%entries(i)%name = timer_name(i, name_len)
         summary%entries(i)%depth = 0
         summary%entries(i)%participating_rank_count = participating_ranks
         summary%entries(i)%min_inclusive_time = real(i, wp)*0.001_wp
         summary%entries(i)%avg_inclusive_time = real(i, wp)*0.0015_wp
         summary%entries(i)%max_inclusive_time = real(i, wp)*0.002_wp
         summary%entries(i)%inclusive_imbalance = 0.1_wp
         summary%entries(i)%min_self_time = real(i, wp)*0.0005_wp
         summary%entries(i)%avg_self_time = real(i, wp)*0.001_wp
         summary%entries(i)%max_self_time = real(i, wp)*0.0015_wp
         summary%entries(i)%self_imbalance = 0.1_wp
         summary%entries(i)%min_call_count = int(i, int64)
         summary%entries(i)%avg_call_count = real(i, wp) + 0.5_wp
         summary%entries(i)%max_call_count = int(i + participating_ranks, int64)
         summary%entries(i)%min_pct_time = 0.1_wp
         summary%entries(i)%avg_pct_time = 0.2_wp
         summary%entries(i)%max_pct_time = 0.3_wp
         summary%entries(i)%node_id = i
         summary%entries(i)%parent_id = 0
         summary%entries(i)%min_inclusive_time_rank = 0
         summary%entries(i)%max_inclusive_time_rank = participating_ranks - 1
      end do
   end subroutine build_mpi_union_summary_fixture

   function timer_name(index, name_len) result(name)
      integer, intent(in) :: index
      integer, intent(in) :: name_len
      character(len=:), allocatable :: name
      character(len=32) :: index_text
      integer :: suffix_len

      write (index_text, '(i0)') index
      suffix_len = len_trim(index_text)
      name = repeat('t', max(name_len, suffix_len))
      name(len(name) - suffix_len + 1:len(name)) = trim(index_text)
      if (len(name) > name_len) name = name(len(name) - name_len + 1:len(name))
   end function timer_name

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
      if (is_reporting_rank()) then
         write (*, '(a47,i10,f12.2,f13.1)') label, reps, total_ms, per_op_ns
         call write_csv_result(label, reps, total_ms, per_op_ns)
      end if
   end subroutine print_result

end program ftimer_bench
