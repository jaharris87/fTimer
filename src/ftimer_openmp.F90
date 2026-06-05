module ftimer_openmp
   use, intrinsic :: iso_fortran_env, only: error_unit, int64, iostat_end, output_unit
   use ftimer_clock, only: ftimer_date_string, ftimer_default_clock
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_INVALID_NAME, FTIMER_ERR_IO, FTIMER_ERR_MISMATCH, &
                           FTIMER_ERR_MPI_INCON, FTIMER_ERR_NOT_IMPLEMENTED, FTIMER_ERR_NOT_INIT, &
                           FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS, &
                           ftimer_call_stack_t, ftimer_clock_func, ftimer_metadata_t, ftimer_segment_t, wp
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Allgather, MPI_Allgatherv, MPI_Allreduce, MPI_Bcast, MPI_Comm, MPI_COMM_NULL, MPI_COMM_SELF, &
                      MPI_COMM_WORLD, MPI_Datatype, MPI_DATATYPE_NULL, MPI_Errhandler, MPI_Errhandler_free, &
                      MPI_ERRORS_RETURN, MPI_Comm_get_errhandler, MPI_Comm_rank, MPI_Comm_set_errhandler, &
                      MPI_Comm_size, MPI_CHARACTER, MPI_INTEGER, MPI_MAX, MPI_MIN, MPI_SUCCESS, MPI_SUM, &
                      MPI_TYPECLASS_INTEGER, MPI_TYPECLASS_REAL, MPI_Type_match_size, MPI_Type_size
#endif
#ifdef FTIMER_USE_OPENMP
   use omp_lib, only: omp_get_level, omp_get_max_threads, omp_get_num_threads, omp_get_thread_num, omp_in_parallel
#endif
   implicit none
   private

   public :: FTIMER_OPENMP_MODE_THREAD_LANES
   public :: ftimer_openmp_config_t
   public :: ftimer_openmp_parallel_region_t
   public :: ftimer_mpi_openmp_rank_t
   public :: ftimer_mpi_openmp_summary_entry_t
   public :: ftimer_mpi_openmp_summary_t
   public :: ftimer_mpi_openmp_union_rank_t
   public :: ftimer_mpi_openmp_union_summary_entry_t
   public :: ftimer_mpi_openmp_union_summary_t
   public :: ftimer_openmp_summary_entry_t
   public :: ftimer_openmp_summary_t
   public :: ftimer_openmp_t

   integer, parameter :: FTIMER_OPENMP_MODE_THREAD_LANES = 1
   integer, parameter :: FTIMER_OPENMP_CATALOG_INITIAL_CAPACITY = 16
   integer, parameter :: FTIMER_OPENMP_DEFAULT_WORKER_DIAGNOSTICS = 32
   integer, parameter :: FTIMER_OPENMP_CONTEXT_EPOCH_UNKNOWN = -1
   character(len=*), parameter :: FTIMER_OPENMP_CSV_FORMAT_VERSION = '1'
   character(len=*), parameter :: FTIMER_MPI_OPENMP_CSV_FORMAT_VERSION = '1'
   character(len=*), parameter :: FTIMER_MPI_OPENMP_UNION_CSV_FORMAT_VERSION = '1'
   integer, parameter :: default_report_buffer_capacity = 1024
   integer(int64) :: next_object_token = 1_int64
   integer(int64) :: next_region_token = 1_int64

   type :: openmp_report_buffer_t
      character(len=:), allocatable :: chars
      integer :: used = 0
   end type openmp_report_buffer_t

   type :: ftimer_openmp_config_t
      integer :: mode = FTIMER_OPENMP_MODE_THREAD_LANES
      integer :: max_lanes = 0
      integer :: max_worker_diagnostics = FTIMER_OPENMP_DEFAULT_WORKER_DIAGNOSTICS
   end type ftimer_openmp_config_t

   type :: ftimer_openmp_parallel_region_t
      private
      integer :: epoch = 0
      integer(int64) :: object_token = 0_int64
      integer(int64) :: region_token = 0_int64
      logical :: active = .false.
   end type ftimer_openmp_parallel_region_t

   type :: ftimer_openmp_catalog_entry_t
      character(len=:), allocatable :: name
      integer :: id = 0
   end type ftimer_openmp_catalog_entry_t

   type :: ftimer_openmp_init_keyword_guard_t
   end type ftimer_openmp_init_keyword_guard_t

   type :: ftimer_openmp_lane_t
      integer :: lane_id = 0
      logical :: participated = .false.
      type(ftimer_call_stack_t) :: call_stack
      type(ftimer_segment_t), allocatable :: segments(:)
   end type ftimer_openmp_lane_t

   type :: ftimer_openmp_summary_entry_t
      character(len=:), allocatable :: name
      integer :: depth = 0
      integer :: node_id = 0
      integer :: parent_id = 0
      integer :: eligible_lane_count = 0
      integer :: participating_lane_count = 0
      integer :: missing_lane_count = 0
      logical :: missing_lane_count_known = .true.
      real(wp) :: sum_lane_inclusive_time = 0.0_wp
      real(wp) :: sum_lane_self_time = 0.0_wp
      real(wp) :: min_lane_inclusive_time = 0.0_wp
      real(wp) :: avg_lane_inclusive_time = 0.0_wp
      real(wp) :: max_lane_inclusive_time = 0.0_wp
      real(wp) :: lane_inclusive_imbalance = 1.0_wp
      real(wp) :: min_lane_self_time = 0.0_wp
      real(wp) :: avg_lane_self_time = 0.0_wp
      real(wp) :: max_lane_self_time = 0.0_wp
      real(wp) :: lane_self_imbalance = 1.0_wp
      integer(int64) :: min_lane_call_count = 0_int64
      integer(int64) :: max_lane_call_count = 0_int64
      real(wp) :: avg_lane_call_count = 0.0_wp
   end type ftimer_openmp_summary_entry_t

   type :: ftimer_openmp_summary_t
      character(len=40) :: start_date = ''
      character(len=40) :: end_date = ''
      real(wp) :: summary_window_time = 0.0_wp
      real(wp) :: timed_region_envelope_time = 0.0_wp
      real(wp) :: sum_lane_root_inclusive_time = 0.0_wp
      real(wp) :: sum_lane_self_time = 0.0_wp
      integer :: configured_lane_capacity = 0
      integer :: observed_participating_lane_count = 0
      integer :: num_entries = 0
      type(ftimer_openmp_summary_entry_t), allocatable :: entries(:)
   end type ftimer_openmp_summary_t

   type :: ftimer_mpi_openmp_rank_t
      integer :: rank = -1
      integer :: configured_lane_capacity = 0
      integer :: observed_participating_lane_count = 0
      real(wp) :: summary_window_time = 0.0_wp
      real(wp) :: timed_region_envelope_time = 0.0_wp
      real(wp) :: sum_lane_root_inclusive_time = 0.0_wp
      real(wp) :: sum_lane_self_time = 0.0_wp
   end type ftimer_mpi_openmp_rank_t

   type :: ftimer_mpi_openmp_summary_entry_t
      character(len=:), allocatable :: name
      character(len=:), allocatable :: execution_domain
      integer :: depth = 0
      integer :: node_id = 0
      integer :: parent_id = 0
      integer :: participating_rank_count = 0
      integer :: missing_rank_count = 0
      integer :: eligible_rank_lane_sample_count = 0
      integer :: participating_rank_lane_sample_count = 0
      integer :: missing_rank_lane_sample_count = 0
      logical :: missing_rank_lane_sample_count_known = .true.
      real(wp) :: sum_participating_lane_inclusive_time = 0.0_wp
      real(wp) :: sum_participating_lane_self_time = 0.0_wp
      real(wp) :: min_participating_lane_inclusive_time = 0.0_wp
      real(wp) :: avg_participating_lane_inclusive_time = 0.0_wp
      real(wp) :: max_participating_lane_inclusive_time = 0.0_wp
      real(wp) :: participating_lane_inclusive_imbalance = 1.0_wp
      real(wp) :: min_participating_lane_self_time = 0.0_wp
      real(wp) :: avg_participating_lane_self_time = 0.0_wp
      real(wp) :: max_participating_lane_self_time = 0.0_wp
      real(wp) :: participating_lane_self_imbalance = 1.0_wp
      integer(int64) :: min_participating_lane_call_count = 0_int64
      integer(int64) :: max_participating_lane_call_count = 0_int64
      real(wp) :: avg_participating_lane_call_count = 0.0_wp
      real(wp) :: min_participating_lane_pct_time = 0.0_wp
      real(wp) :: avg_participating_lane_pct_time = 0.0_wp
      real(wp) :: max_participating_lane_pct_time = 0.0_wp
      real(wp) :: participating_lane_pct_imbalance = 1.0_wp
   end type ftimer_mpi_openmp_summary_entry_t

   type :: ftimer_mpi_openmp_summary_t
      integer :: num_ranks = 0
      integer :: num_entries = 0
      real(wp) :: min_rank_summary_window_time = 0.0_wp
      real(wp) :: avg_rank_summary_window_time = 0.0_wp
      real(wp) :: max_rank_summary_window_time = 0.0_wp
      real(wp) :: rank_summary_window_imbalance = 1.0_wp
      integer :: min_rank_summary_window_time_rank = -1
      integer :: max_rank_summary_window_time_rank = -1
      real(wp) :: min_rank_timed_region_envelope_time = 0.0_wp
      real(wp) :: avg_rank_timed_region_envelope_time = 0.0_wp
      real(wp) :: max_rank_timed_region_envelope_time = 0.0_wp
      real(wp) :: rank_timed_region_envelope_imbalance = 1.0_wp
      integer :: min_rank_timed_region_envelope_time_rank = -1
      integer :: max_rank_timed_region_envelope_time_rank = -1
      real(wp) :: min_rank_sum_lane_root_inclusive_time = 0.0_wp
      real(wp) :: avg_rank_sum_lane_root_inclusive_time = 0.0_wp
      real(wp) :: max_rank_sum_lane_root_inclusive_time = 0.0_wp
      real(wp) :: rank_sum_lane_root_inclusive_imbalance = 1.0_wp
      integer :: min_rank_sum_lane_root_inclusive_time_rank = -1
      integer :: max_rank_sum_lane_root_inclusive_time_rank = -1
      real(wp) :: min_rank_sum_lane_self_time = 0.0_wp
      real(wp) :: avg_rank_sum_lane_self_time = 0.0_wp
      real(wp) :: max_rank_sum_lane_self_time = 0.0_wp
      real(wp) :: rank_sum_lane_self_imbalance = 1.0_wp
      integer :: min_rank_sum_lane_self_time_rank = -1
      integer :: max_rank_sum_lane_self_time_rank = -1
      type(ftimer_mpi_openmp_rank_t), allocatable :: ranks(:)
      type(ftimer_mpi_openmp_summary_entry_t), allocatable :: entries(:)
   end type ftimer_mpi_openmp_summary_t

   type :: ftimer_mpi_openmp_union_rank_t
      integer :: rank = -1
      integer :: configured_lane_capacity = 0
      integer :: observed_participating_lane_count = 0
      real(wp) :: summary_window_time = 0.0_wp
      real(wp) :: timed_region_envelope_time = 0.0_wp
      real(wp) :: sum_lane_root_inclusive_time = 0.0_wp
      real(wp) :: sum_lane_self_time = 0.0_wp
   end type ftimer_mpi_openmp_union_rank_t

   type :: ftimer_mpi_openmp_union_summary_entry_t
      character(len=:), allocatable :: name
      character(len=:), allocatable :: execution_domain
      integer :: depth = 0
      integer :: node_id = 0
      integer :: parent_id = 0
      integer :: participating_rank_count = 0
      integer :: missing_rank_count = 0
      integer :: eligible_rank_lane_sample_count = 0
      integer :: participating_rank_lane_sample_count = 0
      integer :: missing_rank_lane_sample_count = 0
      logical :: missing_rank_lane_sample_count_known = .true.
      real(wp) :: sum_participating_lane_inclusive_time = 0.0_wp
      real(wp) :: sum_participating_lane_self_time = 0.0_wp
      real(wp) :: min_participating_lane_inclusive_time = 0.0_wp
      real(wp) :: avg_participating_lane_inclusive_time = 0.0_wp
      real(wp) :: max_participating_lane_inclusive_time = 0.0_wp
      real(wp) :: participating_lane_inclusive_imbalance = 1.0_wp
      real(wp) :: min_participating_lane_self_time = 0.0_wp
      real(wp) :: avg_participating_lane_self_time = 0.0_wp
      real(wp) :: max_participating_lane_self_time = 0.0_wp
      real(wp) :: participating_lane_self_imbalance = 1.0_wp
      integer(int64) :: min_participating_lane_call_count = 0_int64
      integer(int64) :: max_participating_lane_call_count = 0_int64
      real(wp) :: avg_participating_lane_call_count = 0.0_wp
      real(wp) :: min_participating_lane_pct_time = 0.0_wp
      real(wp) :: avg_participating_lane_pct_time = 0.0_wp
      real(wp) :: max_participating_lane_pct_time = 0.0_wp
      real(wp) :: participating_lane_pct_imbalance = 1.0_wp
   end type ftimer_mpi_openmp_union_summary_entry_t

   type :: ftimer_mpi_openmp_union_summary_t
      integer :: num_ranks = 0
      integer :: num_entries = 0
      real(wp) :: min_rank_summary_window_time = 0.0_wp
      real(wp) :: avg_rank_summary_window_time = 0.0_wp
      real(wp) :: max_rank_summary_window_time = 0.0_wp
      real(wp) :: rank_summary_window_imbalance = 1.0_wp
      integer :: min_rank_summary_window_time_rank = -1
      integer :: max_rank_summary_window_time_rank = -1
      real(wp) :: min_rank_timed_region_envelope_time = 0.0_wp
      real(wp) :: avg_rank_timed_region_envelope_time = 0.0_wp
      real(wp) :: max_rank_timed_region_envelope_time = 0.0_wp
      real(wp) :: rank_timed_region_envelope_imbalance = 1.0_wp
      integer :: min_rank_timed_region_envelope_time_rank = -1
      integer :: max_rank_timed_region_envelope_time_rank = -1
      real(wp) :: min_rank_sum_lane_root_inclusive_time = 0.0_wp
      real(wp) :: avg_rank_sum_lane_root_inclusive_time = 0.0_wp
      real(wp) :: max_rank_sum_lane_root_inclusive_time = 0.0_wp
      real(wp) :: rank_sum_lane_root_inclusive_imbalance = 1.0_wp
      integer :: min_rank_sum_lane_root_inclusive_time_rank = -1
      integer :: max_rank_sum_lane_root_inclusive_time_rank = -1
      real(wp) :: min_rank_sum_lane_self_time = 0.0_wp
      real(wp) :: avg_rank_sum_lane_self_time = 0.0_wp
      real(wp) :: max_rank_sum_lane_self_time = 0.0_wp
      real(wp) :: rank_sum_lane_self_imbalance = 1.0_wp
      integer :: min_rank_sum_lane_self_time_rank = -1
      integer :: max_rank_sum_lane_self_time_rank = -1
      type(ftimer_mpi_openmp_union_rank_t), allocatable :: ranks(:)
      type(ftimer_mpi_openmp_union_summary_entry_t), allocatable :: entries(:)
   end type ftimer_mpi_openmp_union_summary_t

   type :: mpi_openmp_descriptor_string_t
      character(len=:), allocatable :: value
   end type mpi_openmp_descriptor_string_t

   type :: ftimer_openmp_entry_accumulator_t
      character(len=:), allocatable :: path
      character(len=:), allocatable :: parent_path
      character(len=:), allocatable :: name
      integer :: depth = 0
      logical :: eligible_serial_lane = .false.
      integer :: max_worker_lane_id = 0
      logical :: missing_lane_count_known = .true.
      logical, allocatable :: lane_seen(:)
      real(wp), allocatable :: lane_inclusive(:)
      real(wp), allocatable :: lane_self(:)
      integer(int64), allocatable :: lane_calls(:)
   end type ftimer_openmp_entry_accumulator_t

   type :: ftimer_mpi_openmp_entry_accumulator_t
      character(len=:), allocatable :: path
      character(len=:), allocatable :: parent_path
      character(len=:), allocatable :: descriptor
      character(len=:), allocatable :: parent_descriptor
      character(len=:), allocatable :: name
      character(len=:), allocatable :: execution_domain
      integer :: depth = 0
      integer :: eligible_lane_count = 0
      logical :: missing_lane_count_known = .true.
      logical, allocatable :: lane_seen(:)
      real(wp), allocatable :: lane_inclusive(:)
      real(wp), allocatable :: lane_self(:)
      integer(int64), allocatable :: lane_calls(:)
   end type ftimer_mpi_openmp_entry_accumulator_t

   type :: ftimer_openmp_t
      private
      logical :: initialized = .false.
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_catalog_entry_t), allocatable :: catalog(:)
      integer, allocatable :: id_to_catalog_idx(:)
      integer :: id_index_base = 0
      type(ftimer_openmp_lane_t), allocatable :: lanes(:)
      integer :: num_timers = 0
      integer :: next_timer_id = 1
      integer(int64) :: object_token = 0_int64
      logical :: region_open = .false.
      integer :: current_epoch = 0
      integer(int64) :: current_region_token = 0_int64
      real(wp) :: current_region_start_time = 0.0_wp
      real(wp) :: timed_region_envelope_time = 0.0_wp
      integer :: next_epoch = 1
      integer, allocatable :: epoch_team_size(:)
      integer :: queued_worker_diagnostics = 0
      integer :: worker_diagnostic_overflow = 0
      integer :: first_worker_status = FTIMER_SUCCESS
      real(wp) :: init_wtime = 0.0_wp
      character(len=40) :: init_date = ''
      procedure(ftimer_clock_func), pointer, nopass :: clock => null()
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: mpi_comm = MPI_COMM_WORLD
      logical :: mpi_comm_was_present = .false.
#endif
   contains
      procedure, private :: init_without_comm
#ifdef FTIMER_USE_MPI
      procedure, private :: init_with_mpi_comm
      generic, public :: init => init_without_comm, init_with_mpi_comm
#else
      procedure, public :: init => init_without_comm
#endif
      procedure :: finalize
      procedure :: reset
      procedure :: register_timer
      procedure :: lookup_timer
      procedure :: begin_parallel_region
      procedure :: end_parallel_region
      procedure :: start_id
      procedure :: stop_id
      procedure :: get_openmp_summary
      procedure :: print_openmp_summary
      procedure :: write_openmp_summary
      procedure :: write_openmp_summary_csv
      procedure :: mpi_openmp_summary
      procedure :: print_mpi_openmp_summary
      procedure :: write_mpi_openmp_summary
      procedure :: write_mpi_openmp_summary_csv
      procedure :: mpi_openmp_union_summary
      procedure :: print_mpi_openmp_union_summary
      procedure :: write_mpi_openmp_union_summary
      procedure :: write_mpi_openmp_union_summary_csv
#ifdef FTIMER_BUILD_SMOKE_TESTS
      procedure :: test_lane_total_call_count
      procedure :: test_lane_parent_call_count
      procedure :: test_lane_stack_call_count
      procedure :: test_lane_total_time
      procedure :: test_lane_parent_total_time
      procedure :: test_lane_stack_total_time
      procedure :: test_lane_is_running
      procedure :: test_set_clock
#endif
   end type ftimer_openmp_t

contains

   subroutine init_without_comm(self, keyword_guard, config, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_init_keyword_guard_t), intent(in), optional :: keyword_guard
      type(ftimer_openmp_config_t), intent(in) :: config
      integer, intent(out), optional :: ierr

      if (present(keyword_guard)) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, &
                                  "ftimer_openmp init received an invalid positional guard argument")
         return
      end if

      call init_impl(self, config, ierr=ierr)
   end subroutine init_without_comm

#ifdef FTIMER_USE_MPI
   subroutine init_with_mpi_comm(self, keyword_guard, config, comm, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_init_keyword_guard_t), intent(in), optional :: keyword_guard
      type(ftimer_openmp_config_t), intent(in) :: config
      type(MPI_Comm), intent(in) :: comm
      integer, intent(out), optional :: ierr

      if (present(keyword_guard)) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, &
                                  "ftimer_openmp init received an invalid positional guard argument")
         return
      end if

      call init_impl(self, config, comm=comm, ierr=ierr)
   end subroutine init_with_mpi_comm
#endif

   subroutine init_impl(self, config, ierr, comm)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_config_t), intent(in) :: config
      integer, intent(out), optional :: ierr
#ifdef FTIMER_USE_MPI
      type(MPI_Comm), intent(in), optional :: comm
#else
      integer, intent(in), optional :: comm
#endif
      type(ftimer_openmp_config_t) :: effective_config

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp init called inside an OpenMP parallel region")
         return
      end if

      if (self%initialized .and. self%region_open) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp init with an open timed region; state unchanged")
         return
      end if

      if (self%initialized .and. has_active_lanes(self)) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp init with active lane timers; state unchanged")
         return
      end if

      effective_config = config
      if (.not. normalize_config(effective_config)) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp init with invalid configuration")
         return
      end if

      if (drain_worker_diagnostics(self, ierr)) return
      call ensure_object_token(self)
      if (self%object_token == 0_int64) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp object token space exhausted")
         return
      end if
      call clear_state(self)
      self%initialized = .true.
      self%config = effective_config
      call allocate_lanes(self)
      self%init_wtime = openmp_clock(self)
      self%init_date = ftimer_date_string()
      self%timed_region_envelope_time = 0.0_wp
      self%current_region_start_time = 0.0_wp
#ifdef FTIMER_USE_MPI
      self%mpi_comm = MPI_COMM_WORLD
      self%mpi_comm_was_present = .false.
      if (present(comm)) then
         self%mpi_comm = comm
         self%mpi_comm_was_present = .true.
      end if
#endif

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine init_impl

   subroutine finalize(self, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp finalize called inside an OpenMP parallel region")
         return
      end if

      if (self%region_open) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp finalize with an open timed region; state unchanged")
         return
      end if

      if (self%initialized .and. has_active_lanes(self)) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp finalize with active lane timers; state unchanged")
         return
      end if

      if (drain_worker_diagnostics(self, ierr)) return
      call clear_state(self)
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine finalize

   subroutine reset(self, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr
      type(ftimer_openmp_config_t) :: saved_config
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: saved_mpi_comm
      logical :: saved_mpi_comm_was_present
#endif

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp reset called inside an OpenMP parallel region")
         return
      end if

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp reset before init")
         return
      end if

      if (self%region_open) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp reset with an open timed region; state unchanged")
         return
      end if

      if (has_active_lanes(self)) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp reset with active lane timers; state unchanged")
         return
      end if

      saved_config = self%config
#ifdef FTIMER_USE_MPI
      saved_mpi_comm = self%mpi_comm
      saved_mpi_comm_was_present = self%mpi_comm_was_present
#endif
      if (drain_worker_diagnostics(self, ierr)) return
      self%initialized = .true.
      self%config = saved_config
      self%region_open = .false.
      self%current_epoch = 0
      self%current_region_token = 0_int64
      self%current_region_start_time = 0.0_wp
      self%timed_region_envelope_time = 0.0_wp
      self%next_epoch = 1
      if (allocated(self%epoch_team_size)) deallocate (self%epoch_team_size)
      call clear_all_lanes(self)
      call clear_worker_diagnostics(self)
      self%init_wtime = openmp_clock(self)
      self%init_date = ftimer_date_string()
#ifdef FTIMER_USE_MPI
      self%mpi_comm = saved_mpi_comm
      self%mpi_comm_was_present = saved_mpi_comm_was_present
#endif
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine reset

   subroutine register_timer(self, name, id, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out) :: id
      integer, intent(out), optional :: ierr
      integer :: existing_idx
      integer :: trimmed_len
      integer :: status
      character(len=:), allocatable :: message

      id = 0

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp register_timer called inside an OpenMP parallel region")
         return
      end if

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp register_timer before init")
         return
      end if

      if (self%region_open) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp register_timer with an open timed region")
         return
      end if

      call normalize_name(name, trimmed_len, status, message)
      if (status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, status, message)
         return
      end if

      existing_idx = find_timer_index(self, name(1:trimmed_len))
      if (existing_idx > 0) then
         id = self%catalog(existing_idx)%id
         if (present(ierr)) ierr = FTIMER_SUCCESS
         return
      end if

      id = allocate_timer_id(self)
      if (id <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp timer id space exhausted")
         return
      end if

      call ensure_catalog_capacity(self, self%num_timers + 1)
      self%num_timers = self%num_timers + 1
      self%catalog(self%num_timers)%name = name(1:trimmed_len)
      self%catalog(self%num_timers)%id = id
      call ensure_id_index_capacity(self, id)
      self%id_to_catalog_idx(id - self%id_index_base + 1) = self%num_timers

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine register_timer

   subroutine lookup_timer(self, name, id, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out) :: id
      integer, intent(out), optional :: ierr
      integer :: idx
      integer :: trimmed_len
      integer :: status
      character(len=:), allocatable :: message

      id = 0

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp lookup_timer before init")
         return
      end if

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp lookup_timer called inside an OpenMP parallel region")
         return
      end if

      call normalize_name(name, trimmed_len, status, message)
      if (status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, status, message)
         return
      end if

      idx = find_timer_index(self, name(1:trimmed_len))
      if (idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp lookup_timer with unknown timer name")
         return
      end if

      id = self%catalog(idx)%id
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine lookup_timer

   subroutine begin_parallel_region(self, region, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_parallel_region_t), intent(inout) :: region
      integer, intent(out), optional :: ierr

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp begin_parallel_region before init")
         return
      end if

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp begin_parallel_region called inside an OpenMP parallel region")
         return
      end if

      if (self%region_open) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp begin_parallel_region with another region already open")
         return
      end if

      if (region%active) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp begin_parallel_region with an active region handle")
         return
      end if

      if (has_active_lanes(self)) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp begin_parallel_region with active lane timers")
         return
      end if

      self%current_region_token = allocate_region_token()
      if (self%current_region_token == 0_int64) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp region token space exhausted")
         return
      end if

      self%region_open = .true.
      self%current_epoch = self%next_epoch
      if (self%next_epoch < huge(self%next_epoch)) self%next_epoch = self%next_epoch + 1
      call ensure_epoch_capacity(self, self%current_epoch)
      self%epoch_team_size(self%current_epoch) = 0
      self%current_region_start_time = openmp_clock(self)
      region%epoch = self%current_epoch
      region%object_token = self%object_token
      region%region_token = self%current_region_token
      region%active = .true.
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine begin_parallel_region

   subroutine end_parallel_region(self, region, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_parallel_region_t), intent(inout) :: region
      integer, intent(out), optional :: ierr

      if (.not. self%initialized) then
         if (region_belongs_to_self(self, region)) call clear_region(region)
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp end_parallel_region before init")
         return
      end if

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp end_parallel_region called inside an OpenMP parallel region")
         return
      end if

      if ((.not. self%region_open) .or. (.not. region%active) .or. &
          (region%epoch /= self%current_epoch) .or. &
          (region%object_token /= self%object_token) .or. &
          (region%region_token /= self%current_region_token)) then
         if (region_belongs_to_self(self, region)) call clear_region(region)
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp end_parallel_region without matching open timed region")
         return
      end if

      if (has_active_lanes(self)) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp end_parallel_region with active lane timers")
         return
      end if

      if (drain_worker_diagnostics(self, ierr)) return

      self%timed_region_envelope_time = self%timed_region_envelope_time + &
                                        (openmp_clock(self) - self%current_region_start_time)
      self%region_open = .false.
      self%current_epoch = 0
      self%current_region_token = 0_int64
      self%current_region_start_time = 0.0_wp
      call clear_region(region)

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine end_parallel_region

   subroutine start_id(self, id, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr
      integer :: catalog_idx
      integer :: epoch
      integer :: lane_idx
      integer :: status
      integer :: worker_lane_count

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp start_id before init")
         return
      end if

      catalog_idx = find_timer_id_index(self, id)
      if (catalog_idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp start_id with unknown timer id")
         return
      end if

      status = resolve_timing_lane(self, lane_idx, epoch, worker_lane_count)
      if (status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, status, "ftimer_openmp start_id outside a valid timed lane")
         return
      end if

      call start_lane_timer(self, lane_idx, catalog_idx, id, epoch, worker_lane_count, ierr)
   end subroutine start_id

   subroutine stop_id(self, id, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr
      integer :: catalog_idx
      integer :: epoch
      integer :: lane_idx
      integer :: status
      integer :: worker_lane_count

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp stop_id before init")
         return
      end if

      catalog_idx = find_timer_id_index(self, id)
      if (catalog_idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp stop_id with unknown timer id")
         return
      end if

      status = resolve_timing_lane(self, lane_idx, epoch, worker_lane_count)
      if (status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, status, "ftimer_openmp stop_id outside a valid timed lane")
         return
      end if

      call stop_lane_timer(self, lane_idx, catalog_idx, id, epoch, ierr)
   end subroutine stop_id

   subroutine get_openmp_summary(self, summary, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_summary_t), intent(out) :: summary
      integer, intent(out), optional :: ierr
      integer :: status

      status = prepare_openmp_summary(self, summary, diagnostics_are_explicit=present(ierr))
      if (status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, status, "ftimer_openmp get_openmp_summary failed")
         return
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine get_openmp_summary

   subroutine print_openmp_summary(self, unit, metadata, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in), optional :: unit
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr
      type(ftimer_openmp_summary_t) :: summary
      character(len=:), allocatable :: text
      character(len=256) :: iomsg
      integer :: io
      integer :: out_unit
      integer :: status

      status = prepare_openmp_summary(self, summary, diagnostics_are_explicit=present(ierr))
      if (status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, status, "ftimer_openmp print_openmp_summary summary failed")
         return
      end if

      call format_openmp_summary(summary, text, metadata)
      out_unit = output_unit
      if (present(unit)) out_unit = unit
      call write_text_block(out_unit, text, io, iomsg)
      if (io /= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_IO, &
                                  "ftimer_openmp print_openmp_summary write failed: "//trim(iomsg))
         return
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine print_openmp_summary

   subroutine write_openmp_summary(self, filename, append, metadata, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      character(len=*), intent(in) :: filename
      logical, intent(in), optional :: append
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr
      type(ftimer_openmp_summary_t) :: summary
      character(len=:), allocatable :: text
      character(len=256) :: iomsg
      integer :: file_unit
      integer :: io
      integer :: status
      logical :: append_mode

      status = prepare_openmp_summary(self, summary, diagnostics_are_explicit=present(ierr))
      if (status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, status, "ftimer_openmp write_openmp_summary summary failed")
         return
      end if

      call format_openmp_summary(summary, text, metadata)
      append_mode = .false.
      if (present(append)) append_mode = append

      if (append_mode) then
         open (newunit=file_unit, file=filename, status='unknown', position='append', action='write', iostat=io, iomsg=iomsg)
      else
         open (newunit=file_unit, file=filename, status='replace', action='write', iostat=io, iomsg=iomsg)
      end if
      if (io /= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_IO, &
                                  "ftimer_openmp write_openmp_summary open failed: "//trim(iomsg))
         return
      end if

      call write_text_block(file_unit, text, io, iomsg)
      if (io /= 0) then
         close (file_unit)
         call report_timer_status(self, ierr, FTIMER_ERR_IO, &
                                  "ftimer_openmp write_openmp_summary write failed: "//trim(iomsg))
         return
      end if

      close (file_unit, iostat=io, iomsg=iomsg)
      if (io /= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_IO, &
                                  "ftimer_openmp write_openmp_summary close failed: "//trim(iomsg))
         return
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine write_openmp_summary

   subroutine write_openmp_summary_csv(self, filename, append, metadata, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      character(len=*), intent(in) :: filename
      logical, intent(in), optional :: append
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr
      type(ftimer_openmp_summary_t) :: summary
      character(len=:), allocatable :: text
      character(len=256) :: iomsg
      integer :: file_unit
      integer :: header_status
      integer :: io
      integer :: status
      logical :: append_mode
      logical :: include_header

      status = prepare_openmp_summary(self, summary, diagnostics_are_explicit=present(ierr))
      if (status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, status, "ftimer_openmp write_openmp_summary_csv summary failed")
         return
      end if

      append_mode = .false.
      if (present(append)) append_mode = append
      call get_openmp_csv_header_mode(filename, append_mode, include_header, header_status, iomsg)
      if (header_status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, header_status, &
                                  "ftimer_openmp write_openmp_summary_csv append validation failed: "//trim(iomsg))
         return
      end if

      call format_openmp_summary_csv(summary, text, metadata, include_header=include_header)
      if (append_mode) then
         open (newunit=file_unit, file=filename, status='unknown', position='append', action='write', iostat=io, iomsg=iomsg)
      else
         open (newunit=file_unit, file=filename, status='replace', action='write', iostat=io, iomsg=iomsg)
      end if
      if (io /= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_IO, &
                                  "ftimer_openmp write_openmp_summary_csv open failed: "//trim(iomsg))
         return
      end if

      call write_text_block(file_unit, text, io, iomsg)
      if (io /= 0) then
         close (file_unit)
         call report_timer_status(self, ierr, FTIMER_ERR_IO, &
                                  "ftimer_openmp write_openmp_summary_csv write failed: "//trim(iomsg))
         return
      end if

      close (file_unit, iostat=io, iomsg=iomsg)
      if (io /= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_IO, &
                                  "ftimer_openmp write_openmp_summary_csv close failed: "//trim(iomsg))
         return
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine write_openmp_summary_csv

   subroutine mpi_openmp_summary(self, summary, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_mpi_openmp_summary_t), intent(out) :: summary
      integer, intent(out), optional :: ierr
      character(len=256) :: diagnostic
      integer :: status

      call build_current_mpi_openmp_summary(self, summary, status, diagnostic, present(ierr))
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, status, diagnostic)
         return
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine mpi_openmp_summary

   subroutine print_mpi_openmp_summary(self, unit, metadata, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in), optional :: unit
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr
      type(ftimer_mpi_openmp_summary_t) :: summary
      character(len=:), allocatable :: text
      character(len=256) :: diagnostic
      character(len=256) :: iomsg
      integer :: io
      integer :: out_unit
      integer :: rank
      integer :: status
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: active_comm
      integer :: bcast_status
      integer :: mpierr
      integer :: nprocs
#endif

      call build_current_mpi_openmp_summary(self, summary, status, diagnostic, present(ierr))
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, status, diagnostic)
         return
      end if

#ifdef FTIMER_USE_MPI
      call get_mpi_openmp_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, status, &
                                              "ftimer_openmp print_mpi_openmp_summary communicator lookup failed")
         return
      end if

      bcast_status = FTIMER_SUCCESS
      if (rank == 0) then
         call format_mpi_openmp_summary(summary, text, metadata)
         out_unit = output_unit
         if (present(unit)) out_unit = unit
         call write_text_block(out_unit, text, io, iomsg)
         if (io /= 0) bcast_status = FTIMER_ERR_IO
      end if
      call MPI_Bcast(bcast_status, 1, MPI_INTEGER, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) bcast_status = FTIMER_ERR_UNKNOWN
      if (bcast_status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, bcast_status, &
                                              "ftimer_openmp print_mpi_openmp_summary write failed")
         return
      end if
#else
      rank = 0
#endif

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine print_mpi_openmp_summary

   subroutine write_mpi_openmp_summary(self, filename, append, metadata, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      character(len=*), intent(in) :: filename
      logical, intent(in), optional :: append
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr
      type(ftimer_mpi_openmp_summary_t) :: summary
      character(len=:), allocatable :: text
      character(len=256) :: collective_message
      character(len=256) :: diagnostic
      character(len=256) :: iomsg
      integer :: file_unit
      integer :: io
      integer :: rank
      integer :: status
      logical :: append_mode
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: active_comm
      integer :: bcast_status
      integer :: mpierr
      integer :: nprocs
#endif

      call build_current_mpi_openmp_summary(self, summary, status, diagnostic, present(ierr))
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, status, diagnostic)
         return
      end if

#ifdef FTIMER_USE_MPI
      call get_mpi_openmp_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, status, &
                                              "ftimer_openmp write_mpi_openmp_summary communicator lookup failed")
         return
      end if

      bcast_status = FTIMER_SUCCESS
      collective_message = ''
      if (rank == 0) then
         call format_mpi_openmp_summary(summary, text, metadata)
         append_mode = .false.
         if (present(append)) append_mode = append
         if (append_mode) then
            open (newunit=file_unit, file=filename, status='unknown', position='append', action='write', &
                  iostat=io, iomsg=iomsg)
         else
            open (newunit=file_unit, file=filename, status='replace', action='write', iostat=io, iomsg=iomsg)
         end if
         if (io /= 0) then
            bcast_status = FTIMER_ERR_IO
            collective_message = "ftimer_openmp write_mpi_openmp_summary open failed: "//trim(iomsg)
         else
            call write_text_block(file_unit, text, io, iomsg)
            if (io /= 0) then
               bcast_status = FTIMER_ERR_IO
               collective_message = "ftimer_openmp write_mpi_openmp_summary write failed: "//trim(iomsg)
               close (file_unit)
            else
               close (file_unit, iostat=io, iomsg=iomsg)
               if (io /= 0) then
                  bcast_status = FTIMER_ERR_IO
                  collective_message = "ftimer_openmp write_mpi_openmp_summary close failed: "//trim(iomsg)
               end if
            end if
         end if
      end if
      call MPI_Bcast(bcast_status, 1, MPI_INTEGER, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, FTIMER_ERR_UNKNOWN, &
                                              "ftimer_openmp write_mpi_openmp_summary status sync failed")
         return
      end if
      call MPI_Bcast(collective_message, len(collective_message), MPI_CHARACTER, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, FTIMER_ERR_UNKNOWN, &
                                              "ftimer_openmp write_mpi_openmp_summary message sync failed")
         return
      end if
      if (bcast_status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, bcast_status, trim(collective_message))
         return
      end if
#else
      rank = 0
#endif

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine write_mpi_openmp_summary

   subroutine write_mpi_openmp_summary_csv(self, filename, append, metadata, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      character(len=*), intent(in) :: filename
      logical, intent(in), optional :: append
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr
      type(ftimer_mpi_openmp_summary_t) :: summary
      character(len=:), allocatable :: text
      character(len=256) :: collective_message
      character(len=256) :: diagnostic
      character(len=256) :: iomsg
      integer :: file_unit
      integer :: header_status
      integer :: io
      integer :: rank
      integer :: status
      logical :: append_mode
      logical :: include_header
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: active_comm
      integer :: bcast_status
      integer :: mpierr
      integer :: nprocs
#endif

      call build_current_mpi_openmp_summary(self, summary, status, diagnostic, present(ierr))
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, status, diagnostic)
         return
      end if

#ifdef FTIMER_USE_MPI
      call get_mpi_openmp_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, status, &
                                              "ftimer_openmp write_mpi_openmp_summary_csv communicator lookup failed")
         return
      end if

      bcast_status = FTIMER_SUCCESS
      collective_message = ''
      if (rank == 0) then
         append_mode = .false.
         if (present(append)) append_mode = append
         call get_mpi_openmp_csv_header_mode(filename, append_mode, include_header, header_status, iomsg)
         if (header_status /= FTIMER_SUCCESS) then
            bcast_status = header_status
            collective_message = "ftimer_openmp write_mpi_openmp_summary_csv append validation failed: "//trim(iomsg)
         else
            call format_mpi_openmp_summary_csv(summary, text, metadata, include_header=include_header)
            if (append_mode) then
               open (newunit=file_unit, file=filename, status='unknown', position='append', action='write', &
                     iostat=io, iomsg=iomsg)
            else
               open (newunit=file_unit, file=filename, status='replace', action='write', iostat=io, iomsg=iomsg)
            end if
            if (io /= 0) then
               bcast_status = FTIMER_ERR_IO
               collective_message = "ftimer_openmp write_mpi_openmp_summary_csv open failed: "//trim(iomsg)
            else
               call write_text_block(file_unit, text, io, iomsg)
               if (io /= 0) then
                  bcast_status = FTIMER_ERR_IO
                  collective_message = "ftimer_openmp write_mpi_openmp_summary_csv write failed: "//trim(iomsg)
                  close (file_unit)
               else
                  close (file_unit, iostat=io, iomsg=iomsg)
                  if (io /= 0) then
                     bcast_status = FTIMER_ERR_IO
                     collective_message = "ftimer_openmp write_mpi_openmp_summary_csv close failed: "//trim(iomsg)
                  end if
               end if
            end if
         end if
      end if
      call MPI_Bcast(bcast_status, 1, MPI_INTEGER, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, FTIMER_ERR_UNKNOWN, &
                                              "ftimer_openmp write_mpi_openmp_summary_csv status sync failed")
         return
      end if
      call MPI_Bcast(collective_message, len(collective_message), MPI_CHARACTER, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, FTIMER_ERR_UNKNOWN, &
                                              "ftimer_openmp write_mpi_openmp_summary_csv message sync failed")
         return
      end if
      if (bcast_status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_summary_error(self, ierr, bcast_status, trim(collective_message))
         return
      end if
#else
      rank = 0
#endif

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine write_mpi_openmp_summary_csv

   subroutine mpi_openmp_union_summary(self, summary, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_mpi_openmp_union_summary_t), intent(out) :: summary
      integer, intent(out), optional :: ierr
      character(len=256) :: diagnostic
      integer :: status

      call build_current_mpi_openmp_union_summary(self, summary, status, diagnostic, present(ierr))
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, status, diagnostic)
         return
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine mpi_openmp_union_summary

   subroutine print_mpi_openmp_union_summary(self, unit, metadata, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in), optional :: unit
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr
      type(ftimer_mpi_openmp_union_summary_t) :: summary
      character(len=:), allocatable :: text
      character(len=256) :: diagnostic
      character(len=256) :: iomsg
      integer :: io
      integer :: out_unit
      integer :: rank
      integer :: status
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: active_comm
      integer :: bcast_status
      integer :: mpierr
      integer :: nprocs
#endif

      call build_current_mpi_openmp_union_summary(self, summary, status, diagnostic, present(ierr))
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, status, diagnostic)
         return
      end if

#ifdef FTIMER_USE_MPI
      call get_mpi_openmp_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, status, &
                                                    "ftimer_openmp print_mpi_openmp_union_summary communicator lookup failed")
         return
      end if

      bcast_status = FTIMER_SUCCESS
      if (rank == 0) then
         call format_mpi_openmp_union_summary(summary, text, metadata)
         out_unit = output_unit
         if (present(unit)) out_unit = unit
         call write_text_block(out_unit, text, io, iomsg)
         if (io /= 0) bcast_status = FTIMER_ERR_IO
      end if
      call MPI_Bcast(bcast_status, 1, MPI_INTEGER, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) bcast_status = FTIMER_ERR_UNKNOWN
      if (bcast_status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, bcast_status, &
                                                    "ftimer_openmp print_mpi_openmp_union_summary write failed")
         return
      end if
#else
      rank = 0
#endif

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine print_mpi_openmp_union_summary

   subroutine write_mpi_openmp_union_summary(self, filename, append, metadata, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      character(len=*), intent(in) :: filename
      logical, intent(in), optional :: append
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr
      type(ftimer_mpi_openmp_union_summary_t) :: summary
      character(len=:), allocatable :: text
      character(len=256) :: collective_message
      character(len=256) :: diagnostic
      character(len=256) :: iomsg
      integer :: file_unit
      integer :: io
      integer :: rank
      integer :: status
      logical :: append_mode
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: active_comm
      integer :: bcast_status
      integer :: mpierr
      integer :: nprocs
#endif

      call build_current_mpi_openmp_union_summary(self, summary, status, diagnostic, present(ierr))
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, status, diagnostic)
         return
      end if

#ifdef FTIMER_USE_MPI
      call get_mpi_openmp_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, status, &
                                                    "ftimer_openmp write_mpi_openmp_union_summary communicator lookup failed")
         return
      end if

      bcast_status = FTIMER_SUCCESS
      collective_message = ''
      if (rank == 0) then
         call format_mpi_openmp_union_summary(summary, text, metadata)
         append_mode = .false.
         if (present(append)) append_mode = append
         if (append_mode) then
            open (newunit=file_unit, file=filename, status='unknown', position='append', action='write', &
                  iostat=io, iomsg=iomsg)
         else
            open (newunit=file_unit, file=filename, status='replace', action='write', iostat=io, iomsg=iomsg)
         end if
         if (io /= 0) then
            bcast_status = FTIMER_ERR_IO
            collective_message = "ftimer_openmp write_mpi_openmp_union_summary open failed: "//trim(iomsg)
         else
            call write_text_block(file_unit, text, io, iomsg)
            if (io /= 0) then
               bcast_status = FTIMER_ERR_IO
               collective_message = "ftimer_openmp write_mpi_openmp_union_summary write failed: "//trim(iomsg)
               close (file_unit)
            else
               close (file_unit, iostat=io, iomsg=iomsg)
               if (io /= 0) then
                  bcast_status = FTIMER_ERR_IO
                  collective_message = "ftimer_openmp write_mpi_openmp_union_summary close failed: "//trim(iomsg)
               end if
            end if
         end if
      end if
      call MPI_Bcast(bcast_status, 1, MPI_INTEGER, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, FTIMER_ERR_UNKNOWN, &
                                                    "ftimer_openmp write_mpi_openmp_union_summary status sync failed")
         return
      end if
      call MPI_Bcast(collective_message, len(collective_message), MPI_CHARACTER, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, FTIMER_ERR_UNKNOWN, &
                                                    "ftimer_openmp write_mpi_openmp_union_summary message sync failed")
         return
      end if
      if (bcast_status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, bcast_status, trim(collective_message))
         return
      end if
#else
      rank = 0
#endif

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine write_mpi_openmp_union_summary

   subroutine write_mpi_openmp_union_summary_csv(self, filename, append, metadata, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      character(len=*), intent(in) :: filename
      logical, intent(in), optional :: append
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr
      type(ftimer_mpi_openmp_union_summary_t) :: summary
      character(len=:), allocatable :: text
      character(len=256) :: collective_message
      character(len=256) :: diagnostic
      character(len=256) :: iomsg
      integer :: file_unit
      integer :: header_status
      integer :: io
      integer :: rank
      integer :: status
      logical :: append_mode
      logical :: include_header
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: active_comm
      integer :: bcast_status
      integer :: mpierr
      integer :: nprocs
#endif

      call build_current_mpi_openmp_union_summary(self, summary, status, diagnostic, present(ierr))
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, status, diagnostic)
         return
      end if

#ifdef FTIMER_USE_MPI
      call get_mpi_openmp_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
      if (status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, status, &
                                                    "ftimer_openmp write_mpi_openmp_union_summary_csv communicator lookup failed")
         return
      end if

      bcast_status = FTIMER_SUCCESS
      collective_message = ''
      if (rank == 0) then
         append_mode = .false.
         if (present(append)) append_mode = append
         call get_mpi_openmp_union_csv_header_mode(filename, append_mode, include_header, header_status, iomsg)
         if (header_status /= FTIMER_SUCCESS) then
            bcast_status = header_status
            collective_message = "ftimer_openmp write_mpi_openmp_union_summary_csv append validation failed: "// &
                                 trim(iomsg)
         else
            call format_mpi_openmp_union_summary_csv(summary, text, metadata, include_header=include_header)
            if (append_mode) then
               open (newunit=file_unit, file=filename, status='unknown', position='append', action='write', &
                     iostat=io, iomsg=iomsg)
            else
               open (newunit=file_unit, file=filename, status='replace', action='write', iostat=io, iomsg=iomsg)
            end if
            if (io /= 0) then
               bcast_status = FTIMER_ERR_IO
               collective_message = "ftimer_openmp write_mpi_openmp_union_summary_csv open failed: "//trim(iomsg)
            else
               call write_text_block(file_unit, text, io, iomsg)
               if (io /= 0) then
                  bcast_status = FTIMER_ERR_IO
                  collective_message = "ftimer_openmp write_mpi_openmp_union_summary_csv write failed: "//trim(iomsg)
                  close (file_unit)
               else
                  close (file_unit, iostat=io, iomsg=iomsg)
                  if (io /= 0) then
                     bcast_status = FTIMER_ERR_IO
                     collective_message = "ftimer_openmp write_mpi_openmp_union_summary_csv close failed: "//trim(iomsg)
                  end if
               end if
            end if
         end if
      end if
      call MPI_Bcast(bcast_status, 1, MPI_INTEGER, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, FTIMER_ERR_UNKNOWN, &
                                                    "ftimer_openmp write_mpi_openmp_union_summary_csv status sync failed")
         return
      end if
      call MPI_Bcast(collective_message, len(collective_message), MPI_CHARACTER, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, FTIMER_ERR_UNKNOWN, &
                                                    "ftimer_openmp write_mpi_openmp_union_summary_csv message sync failed")
         return
      end if
      if (bcast_status /= FTIMER_SUCCESS) then
         call report_mpi_openmp_union_summary_error(self, ierr, bcast_status, trim(collective_message))
         return
      end if
#else
      rank = 0
#endif

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine write_mpi_openmp_union_summary_csv

   subroutine reset_mpi_openmp_summary(summary)
      type(ftimer_mpi_openmp_summary_t), intent(out) :: summary

      if (allocated(summary%ranks)) deallocate (summary%ranks)
      if (allocated(summary%entries)) deallocate (summary%entries)
      summary%num_ranks = 0
      summary%num_entries = 0
      summary%min_rank_summary_window_time = 0.0_wp
      summary%avg_rank_summary_window_time = 0.0_wp
      summary%max_rank_summary_window_time = 0.0_wp
      summary%rank_summary_window_imbalance = 1.0_wp
      summary%min_rank_summary_window_time_rank = -1
      summary%max_rank_summary_window_time_rank = -1
      summary%min_rank_timed_region_envelope_time = 0.0_wp
      summary%avg_rank_timed_region_envelope_time = 0.0_wp
      summary%max_rank_timed_region_envelope_time = 0.0_wp
      summary%rank_timed_region_envelope_imbalance = 1.0_wp
      summary%min_rank_timed_region_envelope_time_rank = -1
      summary%max_rank_timed_region_envelope_time_rank = -1
      summary%min_rank_sum_lane_root_inclusive_time = 0.0_wp
      summary%avg_rank_sum_lane_root_inclusive_time = 0.0_wp
      summary%max_rank_sum_lane_root_inclusive_time = 0.0_wp
      summary%rank_sum_lane_root_inclusive_imbalance = 1.0_wp
      summary%min_rank_sum_lane_root_inclusive_time_rank = -1
      summary%max_rank_sum_lane_root_inclusive_time_rank = -1
      summary%min_rank_sum_lane_self_time = 0.0_wp
      summary%avg_rank_sum_lane_self_time = 0.0_wp
      summary%max_rank_sum_lane_self_time = 0.0_wp
      summary%rank_sum_lane_self_imbalance = 1.0_wp
      summary%min_rank_sum_lane_self_time_rank = -1
      summary%max_rank_sum_lane_self_time_rank = -1
   end subroutine reset_mpi_openmp_summary

   subroutine reset_mpi_openmp_union_summary(summary)
      type(ftimer_mpi_openmp_union_summary_t), intent(out) :: summary

      if (allocated(summary%ranks)) deallocate (summary%ranks)
      if (allocated(summary%entries)) deallocate (summary%entries)
      summary%num_ranks = 0
      summary%num_entries = 0
      summary%min_rank_summary_window_time = 0.0_wp
      summary%avg_rank_summary_window_time = 0.0_wp
      summary%max_rank_summary_window_time = 0.0_wp
      summary%rank_summary_window_imbalance = 1.0_wp
      summary%min_rank_summary_window_time_rank = -1
      summary%max_rank_summary_window_time_rank = -1
      summary%min_rank_timed_region_envelope_time = 0.0_wp
      summary%avg_rank_timed_region_envelope_time = 0.0_wp
      summary%max_rank_timed_region_envelope_time = 0.0_wp
      summary%rank_timed_region_envelope_imbalance = 1.0_wp
      summary%min_rank_timed_region_envelope_time_rank = -1
      summary%max_rank_timed_region_envelope_time_rank = -1
      summary%min_rank_sum_lane_root_inclusive_time = 0.0_wp
      summary%avg_rank_sum_lane_root_inclusive_time = 0.0_wp
      summary%max_rank_sum_lane_root_inclusive_time = 0.0_wp
      summary%rank_sum_lane_root_inclusive_imbalance = 1.0_wp
      summary%min_rank_sum_lane_root_inclusive_time_rank = -1
      summary%max_rank_sum_lane_root_inclusive_time_rank = -1
      summary%min_rank_sum_lane_self_time = 0.0_wp
      summary%avg_rank_sum_lane_self_time = 0.0_wp
      summary%max_rank_sum_lane_self_time = 0.0_wp
      summary%rank_sum_lane_self_imbalance = 1.0_wp
      summary%min_rank_sum_lane_self_time_rank = -1
      summary%max_rank_sum_lane_self_time_rank = -1
   end subroutine reset_mpi_openmp_union_summary

   subroutine get_mpi_openmp_comm_info(comm, active_comm, rank, nprocs, status)
#ifdef FTIMER_USE_MPI
      type(MPI_Comm), intent(in) :: comm
      type(MPI_Comm), intent(out) :: active_comm
#else
      integer, intent(in) :: comm
      integer, intent(out) :: active_comm
#endif
      integer, intent(out) :: rank
      integer, intent(out) :: nprocs
      integer, intent(out) :: status
#ifdef FTIMER_USE_MPI
      integer :: mpierr

      active_comm = comm
      if (active_comm%MPI_VAL == MPI_COMM_NULL%MPI_VAL) then
         status = FTIMER_ERR_UNKNOWN
         rank = -1
         nprocs = 0
         return
      end if

      call MPI_Comm_rank(active_comm, rank, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         rank = -1
         nprocs = 0
         return
      end if

      call MPI_Comm_size(active_comm, nprocs, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         rank = -1
         nprocs = 0
         return
      end if

      status = FTIMER_SUCCESS
#else
      active_comm = comm
      rank = -1
      nprocs = 0
      status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   end subroutine get_mpi_openmp_comm_info

   subroutine build_current_mpi_openmp_summary(self, summary, status, diagnostic, diagnostics_are_explicit)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_mpi_openmp_summary_t), intent(out) :: summary
      integer, intent(out) :: status
      character(len=*), intent(out) :: diagnostic
      logical, intent(in) :: diagnostics_are_explicit
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: active_comm
      type(MPI_Datatype) :: mpi_int64_type
      type(MPI_Datatype) :: mpi_wp_type
      type(ftimer_openmp_summary_t) :: local_summary
      type(ftimer_mpi_openmp_entry_accumulator_t), allocatable :: accumulators(:)
      character(len=:), allocatable :: descriptors(:)
      integer, allocatable :: all_rank_ints(:)
      integer, allocatable :: eligible_samples(:)
      integer, allocatable :: local_eligible_samples(:)
      integer, allocatable :: local_participating_samples(:)
      integer, allocatable :: local_present(:)
      integer, allocatable :: local_max_inclusive_rank(:)
      integer, allocatable :: local_min_inclusive_rank(:)
      integer, allocatable :: max_inclusive_rank(:)
      integer, allocatable :: min_inclusive_rank(:)
      integer, allocatable :: mismatch_flags(:)
      integer, allocatable :: order(:)
      integer, allocatable :: participating_ranks(:)
      integer, allocatable :: participating_samples(:)
      integer(int64), allocatable :: local_calls_max(:)
      integer(int64), allocatable :: local_calls_min(:)
      integer(int64), allocatable :: max_calls(:)
      integer(int64), allocatable :: min_calls(:)
      integer :: acc_idx
      integer :: all_datatypes_ready
      integer :: all_initialized
      integer :: any_active
      integer :: any_hash_mismatch
      integer :: any_strict_invalid
      integer :: collective_status
      integer :: datatypes_ready
      integer :: entry_count
      integer :: i
      integer :: lane_idx
      integer :: local_active
      integer :: local_hash_mismatch
      integer :: local_initialized
      integer :: local_status
      integer :: local_strict_invalid
      integer :: mpierr
      integer :: nprocs
      integer :: rank
      integer :: rank_slot
      integer :: sample_count
      integer(int64) :: local_hashes(2)
      integer(int64) :: reference_hashes(2)
      logical :: did_drain
      real(wp), allocatable :: all_rank_reals(:)
      real(wp), allocatable :: local_call_delta(:)
      real(wp), allocatable :: local_inclusive_max(:)
      real(wp), allocatable :: local_inclusive_min(:)
      real(wp), allocatable :: local_inclusive_sum(:)
      real(wp), allocatable :: local_pct_max(:)
      real(wp), allocatable :: local_pct_min(:)
      real(wp), allocatable :: local_pct_sum(:)
      real(wp), allocatable :: local_self_max(:)
      real(wp), allocatable :: local_self_min(:)
      real(wp), allocatable :: local_self_sum(:)
      real(wp), allocatable :: max_inclusive(:)
      real(wp), allocatable :: max_pct(:)
      real(wp), allocatable :: max_self(:)
      real(wp), allocatable :: min_inclusive(:)
      real(wp), allocatable :: min_pct(:)
      real(wp), allocatable :: min_self(:)
      real(wp), allocatable :: sum_call_delta(:)
      real(wp), allocatable :: sum_inclusive(:)
      real(wp), allocatable :: sum_pct(:)
      real(wp), allocatable :: sum_self(:)
      real(wp) :: lane_pct
      real(wp) :: local_rank_reals(4)
      integer :: local_rank_ints(3)
#endif

      call reset_mpi_openmp_summary(summary)
      diagnostic = ''

#ifndef FTIMER_USE_MPI
      if (.not. self%initialized) then
         status = FTIMER_ERR_NOT_INIT
         return
      end if
#endif

#ifdef FTIMER_USE_MPI
      if (is_inside_parallel_region()) then
         status = FTIMER_ERR_ACTIVE
         return
      end if

      call get_mpi_openmp_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
      if (status /= FTIMER_SUCCESS) return

      local_initialized = 0
      if (self%initialized) local_initialized = 1
      call MPI_Allreduce(local_initialized, all_initialized, 1, MPI_INTEGER, MPI_MIN, &
                         active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      if (all_initialized /= 1) then
         status = FTIMER_ERR_NOT_INIT
         return
      end if

      local_active = 0
      if (self%region_open .or. has_active_lanes(self)) local_active = 1
      call MPI_Allreduce(local_active, any_active, 1, MPI_INTEGER, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      if (any_active /= 0) then
         status = FTIMER_ERR_ACTIVE
         return
      end if

      local_status = worker_diagnostic_status(self)
      if (diagnostics_are_explicit) then
         if (drain_worker_diagnostics(self, local_status)) then
            continue
         end if
      else if (local_status /= FTIMER_SUCCESS) then
         did_drain = drain_worker_diagnostics_silently(self)
      end if
      call MPI_Allreduce(local_status, collective_status, 1, MPI_INTEGER, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      if (collective_status /= FTIMER_SUCCESS) then
         status = collective_status
         return
      end if

      call build_openmp_summary(self, local_summary)
      call build_mpi_openmp_accumulators(self, accumulators, entry_count)
      call finalize_mpi_openmp_accumulators(accumulators, entry_count, local_strict_invalid)

      call MPI_Allreduce(local_strict_invalid, any_strict_invalid, 1, MPI_INTEGER, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      if (any_strict_invalid /= 0) then
         allocate (mismatch_flags(nprocs))
         call MPI_Allgather(local_strict_invalid, 1, MPI_INTEGER, mismatch_flags, 1, MPI_INTEGER, active_comm, mpierr)
         if (mpierr /= MPI_SUCCESS) then
            status = FTIMER_ERR_UNKNOWN
            return
         end if
         call format_mpi_openmp_mismatch_diagnostic(mismatch_flags, &
                                                    "incomplete lane participation", diagnostic)
         status = FTIMER_ERR_MPI_INCON
         return
      end if

      call resolve_mpi_openmp_datatypes(mpi_wp_type, mpi_int64_type, status, diagnostic)
      datatypes_ready = 0
      if (status == FTIMER_SUCCESS) datatypes_ready = 1
      call MPI_Allreduce(datatypes_ready, all_datatypes_ready, 1, MPI_INTEGER, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      if (all_datatypes_ready /= 1) then
         if (status == FTIMER_SUCCESS) then
            status = FTIMER_ERR_UNKNOWN
            diagnostic = "ftimer_openmp mpi_openmp_summary datatype validation failed on another rank"
         end if
         return
      end if

      call build_mpi_openmp_descriptor_order(accumulators, entry_count, descriptors, order)
      call hash_mpi_openmp_descriptor_list(descriptors, order, local_hashes)
      reference_hashes = local_hashes
      call MPI_Bcast(reference_hashes, 2, mpi_int64_type, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      local_hash_mismatch = 0
      if (any(local_hashes /= reference_hashes)) local_hash_mismatch = 1
      call MPI_Allreduce(local_hash_mismatch, any_hash_mismatch, 1, MPI_INTEGER, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      if (any_hash_mismatch /= 0) then
         allocate (mismatch_flags(nprocs))
         call MPI_Allgather(local_hash_mismatch, 1, MPI_INTEGER, mismatch_flags, 1, MPI_INTEGER, active_comm, mpierr)
         if (mpierr /= MPI_SUCCESS) then
            status = FTIMER_ERR_UNKNOWN
            return
         end if
         call format_mpi_openmp_mismatch_diagnostic(mismatch_flags, "descriptor mismatch", diagnostic)
         status = FTIMER_ERR_MPI_INCON
         return
      end if

      local_rank_reals(1) = local_summary%summary_window_time
      local_rank_reals(2) = local_summary%timed_region_envelope_time
      local_rank_reals(3) = local_summary%sum_lane_root_inclusive_time
      local_rank_reals(4) = local_summary%sum_lane_self_time
      local_rank_ints(1) = rank
      local_rank_ints(2) = local_summary%configured_lane_capacity
      local_rank_ints(3) = local_summary%observed_participating_lane_count
      allocate (all_rank_reals(4*nprocs))
      allocate (all_rank_ints(3*nprocs))
      call MPI_Allgather(local_rank_reals, 4, mpi_wp_type, all_rank_reals, 4, mpi_wp_type, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allgather(local_rank_ints, 3, MPI_INTEGER, all_rank_ints, 3, MPI_INTEGER, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      summary%num_ranks = nprocs
      summary%num_entries = entry_count
      allocate (summary%ranks(nprocs))
      do rank_slot = 1, nprocs
         summary%ranks(rank_slot)%rank = all_rank_ints(3*(rank_slot - 1) + 1)
         summary%ranks(rank_slot)%configured_lane_capacity = all_rank_ints(3*(rank_slot - 1) + 2)
         summary%ranks(rank_slot)%observed_participating_lane_count = all_rank_ints(3*(rank_slot - 1) + 3)
         summary%ranks(rank_slot)%summary_window_time = all_rank_reals(4*(rank_slot - 1) + 1)
         summary%ranks(rank_slot)%timed_region_envelope_time = all_rank_reals(4*(rank_slot - 1) + 2)
         summary%ranks(rank_slot)%sum_lane_root_inclusive_time = all_rank_reals(4*(rank_slot - 1) + 3)
         summary%ranks(rank_slot)%sum_lane_self_time = all_rank_reals(4*(rank_slot - 1) + 4)
      end do
      call set_mpi_openmp_rank_metric(all_rank_reals, all_rank_ints, nprocs, 1, &
                                      summary%min_rank_summary_window_time, &
                                      summary%avg_rank_summary_window_time, &
                                      summary%max_rank_summary_window_time, &
                                      summary%rank_summary_window_imbalance, &
                                      summary%min_rank_summary_window_time_rank, &
                                      summary%max_rank_summary_window_time_rank)
      call set_mpi_openmp_rank_metric(all_rank_reals, all_rank_ints, nprocs, 2, &
                                      summary%min_rank_timed_region_envelope_time, &
                                      summary%avg_rank_timed_region_envelope_time, &
                                      summary%max_rank_timed_region_envelope_time, &
                                      summary%rank_timed_region_envelope_imbalance, &
                                      summary%min_rank_timed_region_envelope_time_rank, &
                                      summary%max_rank_timed_region_envelope_time_rank)
      call set_mpi_openmp_rank_metric(all_rank_reals, all_rank_ints, nprocs, 3, &
                                      summary%min_rank_sum_lane_root_inclusive_time, &
                                      summary%avg_rank_sum_lane_root_inclusive_time, &
                                      summary%max_rank_sum_lane_root_inclusive_time, &
                                      summary%rank_sum_lane_root_inclusive_imbalance, &
                                      summary%min_rank_sum_lane_root_inclusive_time_rank, &
                                      summary%max_rank_sum_lane_root_inclusive_time_rank)
      call set_mpi_openmp_rank_metric(all_rank_reals, all_rank_ints, nprocs, 4, &
                                      summary%min_rank_sum_lane_self_time, &
                                      summary%avg_rank_sum_lane_self_time, &
                                      summary%max_rank_sum_lane_self_time, &
                                      summary%rank_sum_lane_self_imbalance, &
                                      summary%min_rank_sum_lane_self_time_rank, &
                                      summary%max_rank_sum_lane_self_time_rank)

      if (entry_count <= 0) then
         allocate (summary%entries(0))
         status = FTIMER_SUCCESS
         return
      end if

      allocate (local_present(entry_count))
      allocate (local_eligible_samples(entry_count))
      allocate (local_participating_samples(entry_count))
      allocate (participating_ranks(entry_count))
      allocate (eligible_samples(entry_count))
      allocate (participating_samples(entry_count))
      allocate (local_inclusive_min(entry_count))
      allocate (local_inclusive_max(entry_count))
      allocate (local_inclusive_sum(entry_count))
      allocate (min_inclusive(entry_count))
      allocate (max_inclusive(entry_count))
      allocate (sum_inclusive(entry_count))
      allocate (local_self_min(entry_count))
      allocate (local_self_max(entry_count))
      allocate (local_self_sum(entry_count))
      allocate (min_self(entry_count))
      allocate (max_self(entry_count))
      allocate (sum_self(entry_count))
      allocate (local_pct_min(entry_count))
      allocate (local_pct_max(entry_count))
      allocate (local_pct_sum(entry_count))
      allocate (min_pct(entry_count))
      allocate (max_pct(entry_count))
      allocate (sum_pct(entry_count))
      allocate (local_calls_min(entry_count))
      allocate (local_calls_max(entry_count))
      allocate (min_calls(entry_count))
      allocate (max_calls(entry_count))
      allocate (local_call_delta(entry_count))
      allocate (sum_call_delta(entry_count))
      allocate (local_min_inclusive_rank(entry_count))
      allocate (local_max_inclusive_rank(entry_count))
      allocate (min_inclusive_rank(entry_count))
      allocate (max_inclusive_rank(entry_count))

      local_present = 1
      local_eligible_samples = 0
      local_participating_samples = 0
      local_inclusive_min = huge(1.0_wp)
      local_inclusive_max = -huge(1.0_wp)
      local_inclusive_sum = 0.0_wp
      local_self_min = huge(1.0_wp)
      local_self_max = -huge(1.0_wp)
      local_self_sum = 0.0_wp
      local_pct_min = huge(1.0_wp)
      local_pct_max = -huge(1.0_wp)
      local_pct_sum = 0.0_wp
      local_calls_min = huge(0_int64)
      local_calls_max = -huge(0_int64)
      local_call_delta = 0.0_wp

      do i = 1, entry_count
         acc_idx = order(i)
         local_eligible_samples(i) = accumulators(acc_idx)%eligible_lane_count
         sample_count = count(accumulators(acc_idx)%lane_seen)
         local_participating_samples(i) = sample_count
         do lane_idx = 1, size(accumulators(acc_idx)%lane_seen)
            if (.not. accumulators(acc_idx)%lane_seen(lane_idx)) cycle
            local_inclusive_sum(i) = local_inclusive_sum(i) + accumulators(acc_idx)%lane_inclusive(lane_idx)
            local_self_sum(i) = local_self_sum(i) + accumulators(acc_idx)%lane_self(lane_idx)
            local_inclusive_min(i) = min(local_inclusive_min(i), accumulators(acc_idx)%lane_inclusive(lane_idx))
            local_inclusive_max(i) = max(local_inclusive_max(i), accumulators(acc_idx)%lane_inclusive(lane_idx))
            local_self_min(i) = min(local_self_min(i), accumulators(acc_idx)%lane_self(lane_idx))
            local_self_max(i) = max(local_self_max(i), accumulators(acc_idx)%lane_self(lane_idx))
            local_calls_min(i) = min(local_calls_min(i), accumulators(acc_idx)%lane_calls(lane_idx))
            local_calls_max(i) = max(local_calls_max(i), accumulators(acc_idx)%lane_calls(lane_idx))
            lane_pct = 0.0_wp
            if (local_summary%summary_window_time > 0.0_wp) then
               lane_pct = 100.0_wp*accumulators(acc_idx)%lane_inclusive(lane_idx)/ &
                          local_summary%summary_window_time
            end if
            local_pct_sum(i) = local_pct_sum(i) + lane_pct
            local_pct_min(i) = min(local_pct_min(i), lane_pct)
            local_pct_max(i) = max(local_pct_max(i), lane_pct)
         end do
      end do

      call MPI_Allreduce(local_present, participating_ranks, entry_count, MPI_INTEGER, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_eligible_samples, eligible_samples, entry_count, MPI_INTEGER, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_participating_samples, participating_samples, entry_count, MPI_INTEGER, MPI_SUM, &
                         active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_inclusive_min, min_inclusive, entry_count, mpi_wp_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_inclusive_max, max_inclusive, entry_count, mpi_wp_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      local_min_inclusive_rank = huge(0)
      local_max_inclusive_rank = huge(0)
      do i = 1, entry_count
         if (local_inclusive_min(i) == min_inclusive(i)) local_min_inclusive_rank(i) = rank
         if (local_inclusive_max(i) == max_inclusive(i)) local_max_inclusive_rank(i) = rank
      end do
      call MPI_Allreduce(local_min_inclusive_rank, min_inclusive_rank, entry_count, MPI_INTEGER, MPI_MIN, &
                         active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_max_inclusive_rank, max_inclusive_rank, entry_count, MPI_INTEGER, MPI_MIN, &
                         active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_inclusive_sum, sum_inclusive, entry_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_self_min, min_self, entry_count, mpi_wp_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_self_max, max_self, entry_count, mpi_wp_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_self_sum, sum_self, entry_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_pct_min, min_pct, entry_count, mpi_wp_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_pct_max, max_pct, entry_count, mpi_wp_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_pct_sum, sum_pct, entry_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_calls_min, min_calls, entry_count, mpi_int64_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      do i = 1, entry_count
         acc_idx = order(i)
         do lane_idx = 1, size(accumulators(acc_idx)%lane_seen)
            if (.not. accumulators(acc_idx)%lane_seen(lane_idx)) cycle
            local_call_delta(i) = local_call_delta(i) + &
                                  real(accumulators(acc_idx)%lane_calls(lane_idx) - min_calls(i), wp)
         end do
      end do
      call MPI_Allreduce(local_calls_max, max_calls, entry_count, mpi_int64_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_call_delta, sum_call_delta, entry_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      allocate (summary%entries(entry_count))
      do i = 1, entry_count
         acc_idx = order(i)
         summary%entries(i)%name = accumulators(acc_idx)%name
         summary%entries(i)%execution_domain = accumulators(acc_idx)%execution_domain
         summary%entries(i)%depth = accumulators(acc_idx)%depth
         summary%entries(i)%node_id = i
         summary%entries(i)%parent_id = find_ordered_mpi_openmp_descriptor(accumulators(acc_idx)%parent_descriptor, &
                                                                           descriptors, order)
         summary%entries(i)%participating_rank_count = participating_ranks(i)
         summary%entries(i)%missing_rank_count = nprocs - participating_ranks(i)
         summary%entries(i)%eligible_rank_lane_sample_count = eligible_samples(i)
         summary%entries(i)%participating_rank_lane_sample_count = participating_samples(i)
         summary%entries(i)%missing_rank_lane_sample_count = eligible_samples(i) - participating_samples(i)
         summary%entries(i)%missing_rank_lane_sample_count_known = .true.
         summary%entries(i)%sum_participating_lane_inclusive_time = sum_inclusive(i)
         summary%entries(i)%sum_participating_lane_self_time = sum_self(i)
         summary%entries(i)%min_participating_lane_inclusive_time = min_inclusive(i)
         summary%entries(i)%avg_participating_lane_inclusive_time = &
            sum_inclusive(i)/real(participating_samples(i), wp)
         summary%entries(i)%max_participating_lane_inclusive_time = max_inclusive(i)
         summary%entries(i)%participating_lane_inclusive_imbalance = &
            compute_openmp_imbalance(max_inclusive(i), summary%entries(i)%avg_participating_lane_inclusive_time)
         summary%entries(i)%min_participating_lane_self_time = min_self(i)
         summary%entries(i)%avg_participating_lane_self_time = sum_self(i)/real(participating_samples(i), wp)
         summary%entries(i)%max_participating_lane_self_time = max_self(i)
         summary%entries(i)%participating_lane_self_imbalance = &
            compute_openmp_imbalance(max_self(i), summary%entries(i)%avg_participating_lane_self_time)
         summary%entries(i)%min_participating_lane_call_count = min_calls(i)
         summary%entries(i)%max_participating_lane_call_count = max_calls(i)
         summary%entries(i)%avg_participating_lane_call_count = &
            bounded_openmp_call_count_average(sum_call_delta(i), participating_samples(i), min_calls(i), max_calls(i))
         summary%entries(i)%min_participating_lane_pct_time = min_pct(i)
         summary%entries(i)%avg_participating_lane_pct_time = sum_pct(i)/real(participating_samples(i), wp)
         summary%entries(i)%max_participating_lane_pct_time = max_pct(i)
         summary%entries(i)%participating_lane_pct_imbalance = &
            compute_openmp_imbalance(max_pct(i), summary%entries(i)%avg_participating_lane_pct_time)
      end do

      status = FTIMER_SUCCESS
#else
      if (is_inside_parallel_region()) then
         status = FTIMER_ERR_ACTIVE
         return
      end if
      status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   end subroutine build_current_mpi_openmp_summary

   subroutine build_current_mpi_openmp_union_summary(self, summary, status, diagnostic, diagnostics_are_explicit)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_mpi_openmp_union_summary_t), intent(out) :: summary
      integer, intent(out) :: status
      character(len=*), intent(out) :: diagnostic
      logical, intent(in) :: diagnostics_are_explicit
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: active_comm
      type(MPI_Datatype) :: mpi_int64_type
      type(MPI_Datatype) :: mpi_wp_type
      type(ftimer_openmp_summary_t) :: local_summary
      type(ftimer_mpi_openmp_entry_accumulator_t), allocatable :: accumulators(:)
      type(mpi_openmp_descriptor_string_t), allocatable :: union_descriptors(:)
      character(len=:), allocatable :: descriptors(:)
      character(len=:), allocatable :: entry_name
      character(len=:), allocatable :: execution_domain
      character(len=:), allocatable :: parent_descriptor
      integer, allocatable :: all_rank_ints(:)
      integer, allocatable :: eligible_samples(:)
      integer, allocatable :: local_eligible_samples(:)
      integer, allocatable :: local_missing_known(:)
      integer, allocatable :: local_participating_samples(:)
      integer, allocatable :: local_present(:)
      integer, allocatable :: local_to_union(:)
      integer, allocatable :: missing_known(:)
      integer, allocatable :: order(:)
      integer, allocatable :: participating_ranks(:)
      integer, allocatable :: participating_samples(:)
      integer(int64), allocatable :: local_calls_max(:)
      integer(int64), allocatable :: local_calls_min(:)
      integer(int64), allocatable :: max_calls(:)
      integer(int64), allocatable :: min_calls(:)
      integer :: acc_idx
      integer :: all_datatypes_ready
      integer :: all_initialized
      integer :: any_active
      integer :: collective_status
      integer :: datatypes_ready
      integer :: entry_count
      integer :: i
      integer :: lane_idx
      integer :: local_active
      integer :: local_initialized
      integer :: local_status
      integer :: mpierr
      integer :: nprocs
      integer :: parent_id
      integer :: rank
      integer :: rank_slot
      integer :: sample_count
      integer :: union_count
      integer :: union_idx
      logical :: did_drain
      real(wp), allocatable :: all_rank_reals(:)
      real(wp), allocatable :: local_call_delta(:)
      real(wp), allocatable :: local_inclusive_max(:)
      real(wp), allocatable :: local_inclusive_min(:)
      real(wp), allocatable :: local_inclusive_sum(:)
      real(wp), allocatable :: local_pct_max(:)
      real(wp), allocatable :: local_pct_min(:)
      real(wp), allocatable :: local_pct_sum(:)
      real(wp), allocatable :: local_self_max(:)
      real(wp), allocatable :: local_self_min(:)
      real(wp), allocatable :: local_self_sum(:)
      real(wp), allocatable :: max_inclusive(:)
      real(wp), allocatable :: max_pct(:)
      real(wp), allocatable :: max_self(:)
      real(wp), allocatable :: min_inclusive(:)
      real(wp), allocatable :: min_pct(:)
      real(wp), allocatable :: min_self(:)
      real(wp), allocatable :: sum_call_delta(:)
      real(wp), allocatable :: sum_inclusive(:)
      real(wp), allocatable :: sum_pct(:)
      real(wp), allocatable :: sum_self(:)
      real(wp) :: lane_pct
      real(wp) :: local_rank_reals(4)
      integer :: local_rank_ints(3)
#endif

      call reset_mpi_openmp_union_summary(summary)
      diagnostic = ''

#ifndef FTIMER_USE_MPI
      if (.not. self%initialized) then
         status = FTIMER_ERR_NOT_INIT
         return
      end if
#endif

#ifdef FTIMER_USE_MPI
      if (is_inside_parallel_region()) then
         status = FTIMER_ERR_ACTIVE
         return
      end if

      call get_mpi_openmp_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
      if (status /= FTIMER_SUCCESS) return

      local_initialized = 0
      if (self%initialized) local_initialized = 1
      call MPI_Allreduce(local_initialized, all_initialized, 1, MPI_INTEGER, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      if (all_initialized /= 1) then
         status = FTIMER_ERR_NOT_INIT
         return
      end if

      local_active = 0
      if (self%region_open .or. has_active_lanes(self)) local_active = 1
      call MPI_Allreduce(local_active, any_active, 1, MPI_INTEGER, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      if (any_active /= 0) then
         status = FTIMER_ERR_ACTIVE
         return
      end if

      local_status = worker_diagnostic_status(self)
      if (diagnostics_are_explicit) then
         if (drain_worker_diagnostics(self, local_status)) then
            continue
         end if
      else if (local_status /= FTIMER_SUCCESS) then
         did_drain = drain_worker_diagnostics_silently(self)
      end if
      call MPI_Allreduce(local_status, collective_status, 1, MPI_INTEGER, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      if (collective_status /= FTIMER_SUCCESS) then
         status = collective_status
         return
      end if

      call resolve_mpi_openmp_datatypes(mpi_wp_type, mpi_int64_type, status, diagnostic)
      datatypes_ready = 0
      if (status == FTIMER_SUCCESS) datatypes_ready = 1
      call MPI_Allreduce(datatypes_ready, all_datatypes_ready, 1, MPI_INTEGER, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      if (all_datatypes_ready /= 1) then
         if (status == FTIMER_SUCCESS) then
            status = FTIMER_ERR_UNKNOWN
            diagnostic = "ftimer_openmp mpi_openmp_union_summary datatype validation failed on another rank"
         end if
         return
      end if

      call build_openmp_summary(self, local_summary)
      call build_mpi_openmp_accumulators(self, accumulators, entry_count)
      call finalize_mpi_openmp_union_accumulators(accumulators, entry_count)
      call build_mpi_openmp_descriptor_order(accumulators, entry_count, descriptors, order)
      call build_mpi_openmp_union_descriptor_list(descriptors, order, nprocs, active_comm, union_descriptors, &
                                                  union_count, local_to_union, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      local_rank_reals(1) = local_summary%summary_window_time
      local_rank_reals(2) = local_summary%timed_region_envelope_time
      local_rank_reals(3) = local_summary%sum_lane_root_inclusive_time
      local_rank_reals(4) = local_summary%sum_lane_self_time
      local_rank_ints(1) = rank
      local_rank_ints(2) = local_summary%configured_lane_capacity
      local_rank_ints(3) = local_summary%observed_participating_lane_count
      allocate (all_rank_reals(4*nprocs))
      allocate (all_rank_ints(3*nprocs))
      call MPI_Allgather(local_rank_reals, 4, mpi_wp_type, all_rank_reals, 4, mpi_wp_type, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allgather(local_rank_ints, 3, MPI_INTEGER, all_rank_ints, 3, MPI_INTEGER, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      summary%num_ranks = nprocs
      summary%num_entries = union_count
      allocate (summary%ranks(nprocs))
      do rank_slot = 1, nprocs
         summary%ranks(rank_slot)%rank = all_rank_ints(3*(rank_slot - 1) + 1)
         summary%ranks(rank_slot)%configured_lane_capacity = all_rank_ints(3*(rank_slot - 1) + 2)
         summary%ranks(rank_slot)%observed_participating_lane_count = all_rank_ints(3*(rank_slot - 1) + 3)
         summary%ranks(rank_slot)%summary_window_time = all_rank_reals(4*(rank_slot - 1) + 1)
         summary%ranks(rank_slot)%timed_region_envelope_time = all_rank_reals(4*(rank_slot - 1) + 2)
         summary%ranks(rank_slot)%sum_lane_root_inclusive_time = all_rank_reals(4*(rank_slot - 1) + 3)
         summary%ranks(rank_slot)%sum_lane_self_time = all_rank_reals(4*(rank_slot - 1) + 4)
      end do
      call set_mpi_openmp_rank_metric(all_rank_reals, all_rank_ints, nprocs, 1, &
                                      summary%min_rank_summary_window_time, &
                                      summary%avg_rank_summary_window_time, &
                                      summary%max_rank_summary_window_time, &
                                      summary%rank_summary_window_imbalance, &
                                      summary%min_rank_summary_window_time_rank, &
                                      summary%max_rank_summary_window_time_rank)
      call set_mpi_openmp_rank_metric(all_rank_reals, all_rank_ints, nprocs, 2, &
                                      summary%min_rank_timed_region_envelope_time, &
                                      summary%avg_rank_timed_region_envelope_time, &
                                      summary%max_rank_timed_region_envelope_time, &
                                      summary%rank_timed_region_envelope_imbalance, &
                                      summary%min_rank_timed_region_envelope_time_rank, &
                                      summary%max_rank_timed_region_envelope_time_rank)
      call set_mpi_openmp_rank_metric(all_rank_reals, all_rank_ints, nprocs, 3, &
                                      summary%min_rank_sum_lane_root_inclusive_time, &
                                      summary%avg_rank_sum_lane_root_inclusive_time, &
                                      summary%max_rank_sum_lane_root_inclusive_time, &
                                      summary%rank_sum_lane_root_inclusive_imbalance, &
                                      summary%min_rank_sum_lane_root_inclusive_time_rank, &
                                      summary%max_rank_sum_lane_root_inclusive_time_rank)
      call set_mpi_openmp_rank_metric(all_rank_reals, all_rank_ints, nprocs, 4, &
                                      summary%min_rank_sum_lane_self_time, &
                                      summary%avg_rank_sum_lane_self_time, &
                                      summary%max_rank_sum_lane_self_time, &
                                      summary%rank_sum_lane_self_imbalance, &
                                      summary%min_rank_sum_lane_self_time_rank, &
                                      summary%max_rank_sum_lane_self_time_rank)

      if (union_count <= 0) then
         allocate (summary%entries(0))
         status = FTIMER_SUCCESS
         return
      end if

      allocate (local_present(union_count))
      allocate (local_eligible_samples(union_count))
      allocate (local_participating_samples(union_count))
      allocate (local_missing_known(union_count))
      allocate (participating_ranks(union_count))
      allocate (eligible_samples(union_count))
      allocate (participating_samples(union_count))
      allocate (missing_known(union_count))
      allocate (local_inclusive_min(union_count))
      allocate (local_inclusive_max(union_count))
      allocate (local_inclusive_sum(union_count))
      allocate (min_inclusive(union_count))
      allocate (max_inclusive(union_count))
      allocate (sum_inclusive(union_count))
      allocate (local_self_min(union_count))
      allocate (local_self_max(union_count))
      allocate (local_self_sum(union_count))
      allocate (min_self(union_count))
      allocate (max_self(union_count))
      allocate (sum_self(union_count))
      allocate (local_pct_min(union_count))
      allocate (local_pct_max(union_count))
      allocate (local_pct_sum(union_count))
      allocate (min_pct(union_count))
      allocate (max_pct(union_count))
      allocate (sum_pct(union_count))
      allocate (local_calls_min(union_count))
      allocate (local_calls_max(union_count))
      allocate (min_calls(union_count))
      allocate (max_calls(union_count))
      allocate (local_call_delta(union_count))
      allocate (sum_call_delta(union_count))

      local_present = 0
      local_eligible_samples = 0
      local_participating_samples = 0
      local_missing_known = 1
      local_inclusive_min = huge(1.0_wp)
      local_inclusive_max = -huge(1.0_wp)
      local_inclusive_sum = 0.0_wp
      local_self_min = huge(1.0_wp)
      local_self_max = -huge(1.0_wp)
      local_self_sum = 0.0_wp
      local_pct_min = huge(1.0_wp)
      local_pct_max = -huge(1.0_wp)
      local_pct_sum = 0.0_wp
      local_calls_min = huge(0_int64)
      local_calls_max = -huge(0_int64)
      local_call_delta = 0.0_wp

      do i = 1, entry_count
         union_idx = local_to_union(i)
         if (union_idx <= 0) then
            call reset_mpi_openmp_union_summary(summary)
            status = FTIMER_ERR_UNKNOWN
            return
         end if
         acc_idx = order(i)
         local_present(union_idx) = 1
         local_eligible_samples(union_idx) = accumulators(acc_idx)%eligible_lane_count
         sample_count = count(accumulators(acc_idx)%lane_seen)
         local_participating_samples(union_idx) = sample_count
         if (.not. accumulators(acc_idx)%missing_lane_count_known) local_missing_known(union_idx) = 0
         do lane_idx = 1, size(accumulators(acc_idx)%lane_seen)
            if (.not. accumulators(acc_idx)%lane_seen(lane_idx)) cycle
            local_inclusive_sum(union_idx) = local_inclusive_sum(union_idx) + &
                                             accumulators(acc_idx)%lane_inclusive(lane_idx)
            local_self_sum(union_idx) = local_self_sum(union_idx) + accumulators(acc_idx)%lane_self(lane_idx)
            local_inclusive_min(union_idx) = min(local_inclusive_min(union_idx), &
                                                 accumulators(acc_idx)%lane_inclusive(lane_idx))
            local_inclusive_max(union_idx) = max(local_inclusive_max(union_idx), &
                                                 accumulators(acc_idx)%lane_inclusive(lane_idx))
            local_self_min(union_idx) = min(local_self_min(union_idx), accumulators(acc_idx)%lane_self(lane_idx))
            local_self_max(union_idx) = max(local_self_max(union_idx), accumulators(acc_idx)%lane_self(lane_idx))
            local_calls_min(union_idx) = min(local_calls_min(union_idx), accumulators(acc_idx)%lane_calls(lane_idx))
            local_calls_max(union_idx) = max(local_calls_max(union_idx), accumulators(acc_idx)%lane_calls(lane_idx))
            lane_pct = 0.0_wp
            if (local_summary%summary_window_time > 0.0_wp) then
               lane_pct = 100.0_wp*accumulators(acc_idx)%lane_inclusive(lane_idx)/ &
                          local_summary%summary_window_time
            end if
            local_pct_sum(union_idx) = local_pct_sum(union_idx) + lane_pct
            local_pct_min(union_idx) = min(local_pct_min(union_idx), lane_pct)
            local_pct_max(union_idx) = max(local_pct_max(union_idx), lane_pct)
         end do
      end do

      call MPI_Allreduce(local_present, participating_ranks, union_count, MPI_INTEGER, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_eligible_samples, eligible_samples, union_count, MPI_INTEGER, MPI_SUM, &
                         active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_participating_samples, participating_samples, union_count, MPI_INTEGER, MPI_SUM, &
                         active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_missing_known, missing_known, union_count, MPI_INTEGER, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_inclusive_min, min_inclusive, union_count, mpi_wp_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_inclusive_max, max_inclusive, union_count, mpi_wp_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_inclusive_sum, sum_inclusive, union_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_self_min, min_self, union_count, mpi_wp_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_self_max, max_self, union_count, mpi_wp_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_self_sum, sum_self, union_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_pct_min, min_pct, union_count, mpi_wp_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_pct_max, max_pct, union_count, mpi_wp_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_pct_sum, sum_pct, union_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_calls_min, min_calls, union_count, mpi_int64_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      do i = 1, entry_count
         union_idx = local_to_union(i)
         if (union_idx <= 0) then
            call reset_mpi_openmp_union_summary(summary)
            status = FTIMER_ERR_UNKNOWN
            return
         end if
         acc_idx = order(i)
         do lane_idx = 1, size(accumulators(acc_idx)%lane_seen)
            if (.not. accumulators(acc_idx)%lane_seen(lane_idx)) cycle
            local_call_delta(union_idx) = local_call_delta(union_idx) + &
                                          real(accumulators(acc_idx)%lane_calls(lane_idx) - min_calls(union_idx), wp)
         end do
      end do
      call MPI_Allreduce(local_calls_max, max_calls, union_count, mpi_int64_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      call MPI_Allreduce(local_call_delta, sum_call_delta, union_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call reset_mpi_openmp_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      allocate (summary%entries(union_count))
      do i = 1, union_count
         call decode_mpi_openmp_union_descriptor(union_descriptors(i)%value, entry_name, execution_domain, &
                                                 parent_descriptor, summary%entries(i)%depth, status)
         if (status /= FTIMER_SUCCESS) then
            call reset_mpi_openmp_union_summary(summary)
            diagnostic = "ftimer_openmp mpi_openmp_union_summary descriptor decode failed"
            return
         end if
         parent_id = 0
         if (len_trim(parent_descriptor) > 0) then
            parent_id = find_mpi_openmp_union_descriptor(union_descriptors, union_count, parent_descriptor)
            if (parent_id <= 0) then
               call reset_mpi_openmp_union_summary(summary)
               status = FTIMER_ERR_UNKNOWN
               diagnostic = "ftimer_openmp mpi_openmp_union_summary descriptor parent lookup failed"
               return
            end if
         end if

         summary%entries(i)%name = entry_name
         summary%entries(i)%execution_domain = execution_domain
         summary%entries(i)%node_id = i
         summary%entries(i)%parent_id = parent_id
         summary%entries(i)%participating_rank_count = participating_ranks(i)
         summary%entries(i)%missing_rank_count = nprocs - participating_ranks(i)
         summary%entries(i)%eligible_rank_lane_sample_count = eligible_samples(i)
         summary%entries(i)%participating_rank_lane_sample_count = participating_samples(i)
         summary%entries(i)%missing_rank_lane_sample_count_known = (missing_known(i) == 1)
         if (summary%entries(i)%missing_rank_lane_sample_count_known) then
            summary%entries(i)%missing_rank_lane_sample_count = eligible_samples(i) - participating_samples(i)
         else
            summary%entries(i)%missing_rank_lane_sample_count = 0
         end if
         if (participating_samples(i) > 0) then
            summary%entries(i)%sum_participating_lane_inclusive_time = sum_inclusive(i)
            summary%entries(i)%sum_participating_lane_self_time = sum_self(i)
            summary%entries(i)%min_participating_lane_inclusive_time = min_inclusive(i)
            summary%entries(i)%avg_participating_lane_inclusive_time = &
               sum_inclusive(i)/real(participating_samples(i), wp)
            summary%entries(i)%max_participating_lane_inclusive_time = max_inclusive(i)
            summary%entries(i)%participating_lane_inclusive_imbalance = &
               compute_openmp_imbalance(max_inclusive(i), summary%entries(i)%avg_participating_lane_inclusive_time)
            summary%entries(i)%min_participating_lane_self_time = min_self(i)
            summary%entries(i)%avg_participating_lane_self_time = sum_self(i)/real(participating_samples(i), wp)
            summary%entries(i)%max_participating_lane_self_time = max_self(i)
            summary%entries(i)%participating_lane_self_imbalance = &
               compute_openmp_imbalance(max_self(i), summary%entries(i)%avg_participating_lane_self_time)
            summary%entries(i)%min_participating_lane_call_count = min_calls(i)
            summary%entries(i)%max_participating_lane_call_count = max_calls(i)
            summary%entries(i)%avg_participating_lane_call_count = &
               bounded_openmp_call_count_average(sum_call_delta(i), participating_samples(i), min_calls(i), &
                                                 max_calls(i))
            summary%entries(i)%min_participating_lane_pct_time = min_pct(i)
            summary%entries(i)%avg_participating_lane_pct_time = sum_pct(i)/real(participating_samples(i), wp)
            summary%entries(i)%max_participating_lane_pct_time = max_pct(i)
            summary%entries(i)%participating_lane_pct_imbalance = &
               compute_openmp_imbalance(max_pct(i), summary%entries(i)%avg_participating_lane_pct_time)
         end if
      end do

      status = FTIMER_SUCCESS
#else
      if (is_inside_parallel_region()) then
         status = FTIMER_ERR_ACTIVE
         return
      end if
      status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   end subroutine build_current_mpi_openmp_union_summary

   subroutine build_mpi_openmp_accumulators(self, accumulators, entry_count)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_mpi_openmp_entry_accumulator_t), allocatable, intent(out) :: accumulators(:)
      integer, intent(out) :: entry_count
      character(len=:), allocatable :: execution_domain
      character(len=:), allocatable :: parent_path
      character(len=:), allocatable :: path
      integer :: acc_idx
      integer :: catalog_idx
      integer :: ctx
      integer :: eligible_lane_count
      integer :: lane_capacity
      integer :: lane_idx
      logical :: missing_known

      entry_count = 0
      lane_capacity = 0
      if (allocated(self%lanes)) lane_capacity = size(self%lanes)

      do lane_idx = 1, lane_capacity
         if (.not. allocated(self%lanes(lane_idx)%segments)) cycle
         do catalog_idx = 1, min(self%num_timers, size(self%lanes(lane_idx)%segments))
            if (.not. allocated(self%lanes(lane_idx)%segments(catalog_idx)%time)) cycle
            do ctx = 1, self%lanes(lane_idx)%segments(catalog_idx)%contexts%count
               if (.not. context_participates(self%lanes(lane_idx)%segments(catalog_idx), ctx)) cycle

               call mpi_openmp_context_domain(self, self%lanes(lane_idx)%lane_id, &
                                              self%lanes(lane_idx)%segments(catalog_idx)%context_epoch(ctx), &
                                              self%lanes(lane_idx)%segments(catalog_idx)% &
                                              context_max_worker_lane_count(ctx), &
                                              execution_domain, eligible_lane_count, missing_known)
               parent_path = descriptor_path_for_stack(self, &
                                                       self%lanes(lane_idx)%segments(catalog_idx)%contexts%stacks(ctx))
               path = descriptor_path_with_timer(self, parent_path, self%catalog(catalog_idx)%id)
               call find_or_add_mpi_openmp_accumulator(accumulators, entry_count, path, parent_path, &
                                                       self%catalog(catalog_idx)%name, execution_domain, &
                                                       self%lanes(lane_idx)%segments(catalog_idx)%contexts% &
                                                       stacks(ctx)%depth, lane_capacity, acc_idx)
               call add_mpi_openmp_accumulator_sample(accumulators(acc_idx), self%lanes(lane_idx)%lane_id, &
                                                      eligible_lane_count, missing_known, &
                                                      self%lanes(lane_idx)%segments(catalog_idx)%time(ctx), &
                                                      lane_context_self_time(self, lane_idx, catalog_idx, ctx), &
                                                      self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx))
            end do
         end do
      end do

      if (.not. allocated(accumulators)) allocate (accumulators(0))
   end subroutine build_mpi_openmp_accumulators

   subroutine mpi_openmp_context_domain(self, lane_id, epoch, context_worker_lane_count, execution_domain, &
                                        eligible_lane_count, missing_known)
      class(ftimer_openmp_t), intent(in) :: self
      integer, intent(in) :: lane_id
      integer, intent(in) :: epoch
      integer, intent(in) :: context_worker_lane_count
      character(len=:), allocatable, intent(out) :: execution_domain
      integer, intent(out) :: eligible_lane_count
      logical, intent(out) :: missing_known

      missing_known = .true.
      if (lane_id == 0) then
         execution_domain = 'serial_lane'
         eligible_lane_count = 1
      else
         execution_domain = 'openmp_level1_team'
         eligible_lane_count = context_worker_lane_count
         if (eligible_lane_count <= 0) eligible_lane_count = epoch_worker_lane_count(self, epoch)
         if (eligible_lane_count <= 0) then
            eligible_lane_count = lane_id
            missing_known = .false.
         end if
         if (epoch == FTIMER_OPENMP_CONTEXT_EPOCH_UNKNOWN) missing_known = .false.
         eligible_lane_count = max(eligible_lane_count, lane_id)
      end if
   end subroutine mpi_openmp_context_domain

   subroutine find_or_add_mpi_openmp_accumulator(accumulators, entry_count, path, parent_path, name, &
                                                 execution_domain, depth, lane_capacity, idx)
      type(ftimer_mpi_openmp_entry_accumulator_t), allocatable, intent(inout) :: accumulators(:)
      integer, intent(inout) :: entry_count
      character(len=*), intent(in) :: path
      character(len=*), intent(in) :: parent_path
      character(len=*), intent(in) :: name
      character(len=*), intent(in) :: execution_domain
      integer, intent(in) :: depth
      integer, intent(in) :: lane_capacity
      integer, intent(out) :: idx
      type(ftimer_mpi_openmp_entry_accumulator_t), allocatable :: old_accumulators(:)
      integer :: new_size

      if (allocated(accumulators)) then
         do idx = 1, entry_count
            if ((accumulators(idx)%path == path) .and. &
                (accumulators(idx)%execution_domain == execution_domain)) return
         end do
      end if

      if (allocated(accumulators)) then
         if (entry_count >= size(accumulators)) then
            call move_alloc(accumulators, old_accumulators)
            new_size = max(entry_count + 1, 2*size(old_accumulators))
            allocate (accumulators(new_size))
            if (entry_count > 0) accumulators(1:entry_count) = old_accumulators(1:entry_count)
         end if
      else
         allocate (accumulators(max(1, FTIMER_OPENMP_CATALOG_INITIAL_CAPACITY)))
      end if

      entry_count = entry_count + 1
      idx = entry_count
      accumulators(idx)%path = path
      accumulators(idx)%parent_path = parent_path
      accumulators(idx)%name = name
      accumulators(idx)%execution_domain = execution_domain
      accumulators(idx)%depth = depth
      allocate (accumulators(idx)%lane_seen(lane_capacity))
      allocate (accumulators(idx)%lane_inclusive(lane_capacity))
      allocate (accumulators(idx)%lane_self(lane_capacity))
      allocate (accumulators(idx)%lane_calls(lane_capacity))
      accumulators(idx)%lane_seen = .false.
      accumulators(idx)%lane_inclusive = 0.0_wp
      accumulators(idx)%lane_self = 0.0_wp
      accumulators(idx)%lane_calls = 0_int64
   end subroutine find_or_add_mpi_openmp_accumulator

   subroutine add_mpi_openmp_accumulator_sample(accumulator, lane_id, eligible_lane_count, missing_known, &
                                                inclusive_time, self_time, call_count)
      type(ftimer_mpi_openmp_entry_accumulator_t), intent(inout) :: accumulator
      integer, intent(in) :: lane_id
      integer, intent(in) :: eligible_lane_count
      logical, intent(in) :: missing_known
      real(wp), intent(in) :: inclusive_time
      real(wp), intent(in) :: self_time
      integer(int64), intent(in) :: call_count
      integer :: lane_idx

      lane_idx = lane_id + 1
      if ((lane_idx >= 1) .and. (lane_idx <= size(accumulator%lane_seen))) then
         accumulator%lane_seen(lane_idx) = .true.
         accumulator%lane_inclusive(lane_idx) = accumulator%lane_inclusive(lane_idx) + inclusive_time
         accumulator%lane_self(lane_idx) = accumulator%lane_self(lane_idx) + self_time
         accumulator%lane_calls(lane_idx) = accumulator%lane_calls(lane_idx) + call_count
      else
         accumulator%missing_lane_count_known = .false.
      end if

      if (accumulator%eligible_lane_count <= 0) then
         accumulator%eligible_lane_count = eligible_lane_count
      else if (accumulator%eligible_lane_count /= eligible_lane_count) then
         accumulator%eligible_lane_count = max(accumulator%eligible_lane_count, eligible_lane_count)
         accumulator%missing_lane_count_known = .false.
      end if
      if (.not. missing_known) accumulator%missing_lane_count_known = .false.
   end subroutine add_mpi_openmp_accumulator_sample

   subroutine finalize_mpi_openmp_accumulators(accumulators, entry_count, local_strict_invalid)
      type(ftimer_mpi_openmp_entry_accumulator_t), intent(inout) :: accumulators(:)
      integer, intent(in) :: entry_count
      integer, intent(out) :: local_strict_invalid
      integer :: i
      integer :: participating_count

      local_strict_invalid = 0
      do i = 1, entry_count
         participating_count = count(accumulators(i)%lane_seen)
         if ((accumulators(i)%eligible_lane_count <= 0) .or. &
             (participating_count /= accumulators(i)%eligible_lane_count) .or. &
             (.not. accumulators(i)%missing_lane_count_known)) then
            local_strict_invalid = 1
         end if
         accumulators(i)%descriptor = mpi_openmp_descriptor(accumulators(i)%execution_domain, &
                                                            accumulators(i)%eligible_lane_count, &
                                                            accumulators(i)%path)
         if (len(accumulators(i)%parent_path) > 0) then
            accumulators(i)%parent_descriptor = mpi_openmp_descriptor(accumulators(i)%execution_domain, &
                                                                      accumulators(i)%eligible_lane_count, &
                                                                      accumulators(i)%parent_path)
         else
            accumulators(i)%parent_descriptor = ''
         end if
      end do
   end subroutine finalize_mpi_openmp_accumulators

   subroutine finalize_mpi_openmp_union_accumulators(accumulators, entry_count)
      type(ftimer_mpi_openmp_entry_accumulator_t), intent(inout) :: accumulators(:)
      integer, intent(in) :: entry_count
      integer :: i

      do i = 1, entry_count
         accumulators(i)%descriptor = mpi_openmp_union_descriptor(accumulators(i)%execution_domain, &
                                                                  accumulators(i)%path)
         if (len(accumulators(i)%parent_path) > 0) then
            accumulators(i)%parent_descriptor = mpi_openmp_union_descriptor(accumulators(i)%execution_domain, &
                                                                            accumulators(i)%parent_path)
         else
            accumulators(i)%parent_descriptor = ''
         end if
      end do
   end subroutine finalize_mpi_openmp_union_accumulators

   function mpi_openmp_descriptor(execution_domain, eligible_lane_count, path) result(descriptor)
      character(len=*), intent(in) :: execution_domain
      integer, intent(in) :: eligible_lane_count
      character(len=*), intent(in) :: path
      character(len=:), allocatable :: descriptor
      character(len=32) :: eligible_text

      write (eligible_text, '(i0)') eligible_lane_count
      descriptor = 'schema=1|domain='//execution_domain//'|eligible_lanes='//trim(eligible_text)//'|path='//path
   end function mpi_openmp_descriptor

   function mpi_openmp_union_descriptor(execution_domain, path) result(descriptor)
      character(len=*), intent(in) :: execution_domain
      character(len=*), intent(in) :: path
      character(len=:), allocatable :: descriptor

      descriptor = 'schema=1|domain='//execution_domain//'|path='//path
   end function mpi_openmp_union_descriptor

   subroutine build_mpi_openmp_descriptor_order(accumulators, entry_count, descriptors, order)
      type(ftimer_mpi_openmp_entry_accumulator_t), intent(in) :: accumulators(:)
      integer, intent(in) :: entry_count
      character(len=:), allocatable, intent(out) :: descriptors(:)
      integer, allocatable, intent(out) :: order(:)
      integer :: i
      integer :: max_len

      if (entry_count <= 0) then
         allocate (character(len=1) :: descriptors(0))
         allocate (order(0))
         return
      end if

      max_len = 1
      do i = 1, entry_count
         max_len = max(max_len, len(accumulators(i)%descriptor))
      end do
      allocate (character(len=max_len) :: descriptors(entry_count))
      allocate (order(entry_count))
      descriptors = ''
      do i = 1, entry_count
         descriptors(i) = accumulators(i)%descriptor
         order(i) = i
      end do
      call sort_mpi_openmp_descriptor_order(descriptors, order)
   end subroutine build_mpi_openmp_descriptor_order

   subroutine sort_mpi_openmp_descriptor_order(descriptors, order)
      character(len=*), intent(in) :: descriptors(:)
      integer, intent(inout) :: order(:)
      integer :: i
      integer :: j
      integer :: key

      do i = 2, size(order)
         key = order(i)
         j = i - 1
         do while (j >= 1)
            if (descriptors(order(j)) <= descriptors(key)) exit
            order(j + 1) = order(j)
            j = j - 1
         end do
         order(j + 1) = key
      end do
   end subroutine sort_mpi_openmp_descriptor_order

   integer function find_ordered_mpi_openmp_descriptor(descriptor, descriptors, order) result(index_value)
      character(len=*), intent(in) :: descriptor
      character(len=*), intent(in) :: descriptors(:)
      integer, intent(in) :: order(:)
      integer :: i

      index_value = 0
      if (len(descriptor) <= 0) return
      do i = 1, size(order)
         if (descriptors(order(i)) == descriptor) then
            index_value = i
            return
         end if
      end do
   end function find_ordered_mpi_openmp_descriptor

#ifdef FTIMER_USE_MPI
   subroutine build_mpi_openmp_union_descriptor_list(descriptors, order, nprocs, active_comm, union_descriptors, &
                                                     union_count, local_to_union, mpierr)
      character(len=*), intent(in) :: descriptors(:)
      integer, intent(in) :: order(:)
      integer, intent(in) :: nprocs
      type(MPI_Comm), intent(in) :: active_comm
      type(mpi_openmp_descriptor_string_t), allocatable, intent(out) :: union_descriptors(:)
      integer, intent(out) :: union_count
      integer, allocatable, intent(out) :: local_to_union(:)
      integer, intent(out) :: mpierr
      character(len=1), allocatable :: all_descriptor_chars(:)
      character(len=1), allocatable :: local_descriptor_chars(:)
      character(len=:), allocatable :: descriptor_value
      integer, allocatable :: all_descriptor_lengths(:)
      integer, allocatable :: char_counts(:)
      integer, allocatable :: char_displacements(:)
      integer, allocatable :: descriptor_counts(:)
      integer, allocatable :: descriptor_displacements(:)
      integer, allocatable :: local_descriptor_lengths(:)
      integer :: all_mapping_ready
      integer :: all_pack_ready
      integer :: descriptor_len
      integer :: descriptor_offset
      integer :: i
      integer :: j
      integer :: local_char_count
      integer :: local_descriptor_count
      integer :: local_idx
      integer :: local_mapping_ready
      integer :: local_pack_ready
      integer :: next_count
      integer :: offset
      integer :: rank_slot
      integer :: slot
      integer :: total_char_count
      integer :: total_descriptor_count

      mpierr = MPI_SUCCESS
      union_count = 0
      local_descriptor_count = size(order)
      allocate (local_to_union(local_descriptor_count))
      if (local_descriptor_count > 0) local_to_union = 0
      allocate (descriptor_counts(nprocs))
      allocate (descriptor_displacements(nprocs))
      allocate (char_counts(nprocs))
      allocate (char_displacements(nprocs))

      call MPI_Allgather(local_descriptor_count, 1, MPI_INTEGER, descriptor_counts, 1, MPI_INTEGER, &
                         active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) return

      if (.not. build_mpi_openmp_displacements(descriptor_counts, descriptor_displacements, &
                                               total_descriptor_count)) then
         mpierr = -1
         return
      end if
      if (total_descriptor_count <= 0) then
         allocate (union_descriptors(0))
         return
      end if

      allocate (union_descriptors(total_descriptor_count))
      allocate (local_descriptor_lengths(max(local_descriptor_count, 1)))
      allocate (all_descriptor_lengths(total_descriptor_count))
      local_descriptor_lengths = 0
      local_char_count = 0
      local_pack_ready = 1
      do i = 1, local_descriptor_count
         local_idx = order(i)
         descriptor_len = len_trim(descriptors(local_idx))
         local_descriptor_lengths(i) = descriptor_len
         if (local_pack_ready == 1) then
            if (checked_mpi_openmp_int_add(local_char_count, descriptor_len, next_count)) then
               local_char_count = next_count
            else
               local_pack_ready = 0
            end if
         end if
      end do

      call MPI_Allreduce(local_pack_ready, all_pack_ready, 1, MPI_INTEGER, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) return
      if (all_pack_ready /= 1) then
         mpierr = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allgatherv(local_descriptor_lengths, local_descriptor_count, MPI_INTEGER, &
                          all_descriptor_lengths, descriptor_counts, descriptor_displacements, MPI_INTEGER, &
                          active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) return

      char_counts = 0
      do rank_slot = 1, nprocs
         descriptor_offset = descriptor_displacements(rank_slot)
         do slot = 1, descriptor_counts(rank_slot)
            descriptor_len = all_descriptor_lengths(descriptor_offset + slot)
            if (descriptor_len < 0) then
               mpierr = FTIMER_ERR_UNKNOWN
               return
            end if
            if (.not. checked_mpi_openmp_int_add(char_counts(rank_slot), descriptor_len, next_count)) then
               mpierr = FTIMER_ERR_UNKNOWN
               return
            end if
            char_counts(rank_slot) = next_count
         end do
      end do
      if (.not. build_mpi_openmp_displacements(char_counts, char_displacements, total_char_count)) then
         mpierr = FTIMER_ERR_UNKNOWN
         return
      end if

      allocate (local_descriptor_chars(max(local_char_count, 1)))
      allocate (all_descriptor_chars(max(total_char_count, 1)))
      local_descriptor_chars = ' '
      all_descriptor_chars = ' '
      offset = 0
      do i = 1, local_descriptor_count
         local_idx = order(i)
         descriptor_len = local_descriptor_lengths(i)
         do j = 1, descriptor_len
            local_descriptor_chars(offset + j) = descriptors(local_idx) (j:j)
         end do
         offset = offset + descriptor_len
      end do

      call MPI_Allgatherv(local_descriptor_chars, local_char_count, MPI_CHARACTER, all_descriptor_chars, &
                          char_counts, char_displacements, MPI_CHARACTER, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) return

      offset = 0
      do rank_slot = 1, nprocs
         descriptor_offset = descriptor_displacements(rank_slot)
         do slot = 1, descriptor_counts(rank_slot)
            descriptor_len = all_descriptor_lengths(descriptor_offset + slot)
            if (descriptor_len <= 0) cycle
            if (allocated(descriptor_value)) deallocate (descriptor_value)
            allocate (character(len=descriptor_len) :: descriptor_value)
            descriptor_value = repeat(' ', descriptor_len)
            do j = 1, descriptor_len
               descriptor_value(j:j) = all_descriptor_chars(offset + j)
            end do
            offset = offset + descriptor_len
            call add_mpi_openmp_union_descriptor(descriptor_value, union_descriptors, union_count)
         end do
      end do

      local_mapping_ready = 1
      do i = 1, local_descriptor_count
         local_idx = order(i)
         local_to_union(i) = find_mpi_openmp_union_descriptor(union_descriptors, union_count, &
                                                              descriptors(local_idx))
         if (local_to_union(i) <= 0) local_mapping_ready = 0
      end do

      call MPI_Allreduce(local_mapping_ready, all_mapping_ready, 1, MPI_INTEGER, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) return
      if (all_mapping_ready /= 1) then
         mpierr = FTIMER_ERR_UNKNOWN
         return
      end if
   end subroutine build_mpi_openmp_union_descriptor_list
#endif

   logical function build_mpi_openmp_displacements(counts, displacements, total_count) result(ok)
      integer, intent(in) :: counts(:)
      integer, intent(out) :: displacements(:)
      integer, intent(out) :: total_count
      integer :: i
      integer :: next_count

      ok = .true.
      total_count = 0
      do i = 1, size(counts)
         if (counts(i) < 0) then
            ok = .false.
            return
         end if
         displacements(i) = total_count
         if (.not. checked_mpi_openmp_int_add(total_count, counts(i), next_count)) then
            ok = .false.
            return
         end if
         total_count = next_count
      end do
   end function build_mpi_openmp_displacements

   logical function checked_mpi_openmp_int_add(lhs, rhs, sum_value) result(ok)
      integer, intent(in) :: lhs
      integer, intent(in) :: rhs
      integer, intent(out) :: sum_value

      ok = (rhs >= 0) .and. (lhs <= huge(lhs) - rhs)
      if (ok) then
         sum_value = lhs + rhs
      else
         sum_value = huge(sum_value)
      end if
   end function checked_mpi_openmp_int_add

   subroutine add_mpi_openmp_union_descriptor(descriptor, union_descriptors, union_count)
      character(len=*), intent(in) :: descriptor
      type(mpi_openmp_descriptor_string_t), intent(inout) :: union_descriptors(:)
      integer, intent(inout) :: union_count
      integer :: insert_pos
      integer :: j

      insert_pos = union_count + 1
      do j = 1, union_count
         if (descriptor == union_descriptors(j)%value) return
         if (descriptor < union_descriptors(j)%value) then
            insert_pos = j
            exit
         end if
      end do

      union_count = union_count + 1
      do j = union_count, insert_pos + 1, -1
         union_descriptors(j) = union_descriptors(j - 1)
      end do
      union_descriptors(insert_pos)%value = descriptor
   end subroutine add_mpi_openmp_union_descriptor

   integer function find_mpi_openmp_union_descriptor(union_descriptors, union_count, descriptor) result(index_value)
      type(mpi_openmp_descriptor_string_t), intent(in) :: union_descriptors(:)
      integer, intent(in) :: union_count
      character(len=*), intent(in) :: descriptor
      integer :: i

      index_value = 0
      do i = 1, union_count
         if (union_descriptors(i)%value == descriptor) then
            index_value = i
            return
         end if
      end do
   end function find_mpi_openmp_union_descriptor

   subroutine decode_mpi_openmp_union_descriptor(descriptor, name, execution_domain, parent_descriptor, depth, status)
      character(len=*), intent(in) :: descriptor
      character(len=:), allocatable, intent(out) :: name
      character(len=:), allocatable, intent(out) :: execution_domain
      character(len=:), allocatable, intent(out) :: parent_descriptor
      integer, intent(out) :: depth
      integer, intent(out) :: status
      character(len=*), parameter :: prefix = 'schema=1|domain='
      character(len=*), parameter :: path_marker = '|path='
      character(len=:), allocatable :: parent_path
      character(len=:), allocatable :: path
      integer :: domain_start
      integer :: marker_pos
      integer :: path_start
      integer :: text_len

      name = ''
      execution_domain = ''
      parent_descriptor = ''
      depth = 0
      status = FTIMER_ERR_UNKNOWN
      text_len = len_trim(descriptor)
      if (.not. openmp_starts_with(descriptor, prefix)) return

      domain_start = len(prefix) + 1
      marker_pos = index(descriptor, path_marker)
      if (marker_pos <= domain_start) return
      path_start = marker_pos + len(path_marker)
      if (path_start > text_len + 1) return

      execution_domain = descriptor(domain_start:marker_pos - 1)
      if (path_start <= text_len) then
         path = descriptor(path_start:text_len)
      else
         path = ''
      end if
      call decode_mpi_openmp_path(path, name, parent_path, depth, status)
      if (status /= FTIMER_SUCCESS) return
      if (len(parent_path) > 0) parent_descriptor = mpi_openmp_union_descriptor(execution_domain, parent_path)
   end subroutine decode_mpi_openmp_union_descriptor

   subroutine decode_mpi_openmp_path(path, name, parent_path, depth, status)
      character(len=*), intent(in) :: path
      character(len=:), allocatable, intent(out) :: name
      character(len=:), allocatable, intent(out) :: parent_path
      integer, intent(out) :: depth
      integer, intent(out) :: status
      integer :: component_count
      integer :: component_start
      integer :: last_component_start
      integer :: last_name_len
      integer :: last_name_start
      integer :: name_len
      integer :: name_start
      integer :: next_pos
      integer :: pos
      integer :: text_len

      name = ''
      parent_path = ''
      depth = 0
      status = FTIMER_ERR_UNKNOWN
      text_len = len_trim(path)
      pos = 1
      component_count = 0
      last_component_start = 1
      last_name_start = 1
      last_name_len = 0

      do while (pos <= text_len)
         component_start = pos
         if (.not. parse_mpi_openmp_path_component(path, pos, text_len, name_start, name_len, next_pos)) return

         component_count = component_count + 1
         last_component_start = component_start
         last_name_start = name_start
         last_name_len = name_len
         pos = next_pos
         if (pos <= text_len) then
            if (path(pos:pos) /= '/') return
            pos = pos + 1
         end if
      end do

      if (component_count <= 0) return
      depth = max(component_count - 1, 0)
      if (last_name_len > 0) name = path(last_name_start:last_name_start + last_name_len - 1)
      if (last_component_start > 1) parent_path = path(1:last_component_start - 2)
      status = FTIMER_SUCCESS
   end subroutine decode_mpi_openmp_path

   logical function parse_mpi_openmp_path_component(path, start_pos, text_len, name_start, name_len, &
                                                    next_pos) result(is_valid)
      character(len=*), intent(in) :: path
      integer, intent(in) :: start_pos
      integer, intent(in) :: text_len
      integer, intent(out) :: name_start
      integer, intent(out) :: name_len
      integer, intent(out) :: next_pos
      integer :: colon_offset
      integer :: colon_pos
      integer :: io

      is_valid = .false.
      name_start = start_pos
      name_len = 0
      next_pos = start_pos
      if (start_pos > text_len) return

      colon_offset = index(path(start_pos:text_len), ':')
      if (colon_offset <= 0) return
      colon_pos = start_pos + colon_offset - 1
      if (colon_pos <= start_pos) return
      read (path(start_pos:colon_pos - 1), *, iostat=io) name_len
      if (io /= 0) return
      if (name_len < 0) return

      name_start = colon_pos + 1
      next_pos = name_start + name_len
      if (next_pos - 1 > text_len) return
      is_valid = .true.
   end function parse_mpi_openmp_path_component

   subroutine hash_mpi_openmp_descriptor_list(descriptors, order, hash_values)
      character(len=*), intent(in) :: descriptors(:)
      integer, intent(in) :: order(:)
      integer(int64), intent(out) :: hash_values(2)
      integer :: i
      integer :: j
      integer :: trimmed_len
      integer(int64) :: high_hash
      integer(int64) :: low_hash

      high_hash = 2166136261_int64
      low_hash = 1315423911_int64
      high_hash = mpi_openmp_hash_step(high_hash, int(size(order), int64), 16777619_int64, 4294967291_int64)
      low_hash = mpi_openmp_hash_step(low_hash, int(size(order), int64), 65599_int64, 4294967279_int64)
      do i = 1, size(order)
         trimmed_len = len_trim(descriptors(order(i)))
         do j = 1, trimmed_len
            high_hash = mpi_openmp_hash_step(high_hash, int(iachar(descriptors(order(i)) (j:j)), int64), &
                                             16777619_int64, 4294967291_int64)
            low_hash = mpi_openmp_hash_step(low_hash, int(iachar(descriptors(order(i)) (j:j)), int64), &
                                            65599_int64, 4294967279_int64)
         end do
         high_hash = mpi_openmp_hash_step(high_hash, 10_int64, 16777619_int64, 4294967291_int64)
         low_hash = mpi_openmp_hash_step(low_hash, 10_int64, 65599_int64, 4294967279_int64)
      end do
      hash_values(1) = high_hash
      hash_values(2) = low_hash
   end subroutine hash_mpi_openmp_descriptor_list

   integer(int64) function mpi_openmp_hash_step(current, value, base, modulus) result(updated)
      integer(int64), intent(in) :: current
      integer(int64), intent(in) :: value
      integer(int64), intent(in) :: base
      integer(int64), intent(in) :: modulus

      updated = modulo(current*base + value, modulus)
   end function mpi_openmp_hash_step

   subroutine set_mpi_openmp_rank_metric(all_rank_reals, all_rank_ints, nprocs, metric_index, &
                                         min_value, avg_value, max_value, imbalance, min_rank, max_rank)
      real(wp), intent(in) :: all_rank_reals(:)
      integer, intent(in) :: all_rank_ints(:)
      integer, intent(in) :: nprocs
      integer, intent(in) :: metric_index
      real(wp), intent(out) :: min_value
      real(wp), intent(out) :: avg_value
      real(wp), intent(out) :: max_value
      real(wp), intent(out) :: imbalance
      integer, intent(out) :: min_rank
      integer, intent(out) :: max_rank
      integer :: i
      integer :: rank_value
      real(wp) :: sum_value
      real(wp) :: value

      min_value = huge(1.0_wp)
      max_value = -huge(1.0_wp)
      sum_value = 0.0_wp
      min_rank = -1
      max_rank = -1
      do i = 1, nprocs
         value = all_rank_reals(4*(i - 1) + metric_index)
         rank_value = all_rank_ints(3*(i - 1) + 1)
         sum_value = sum_value + value
         if (value < min_value) then
            min_value = value
            min_rank = rank_value
         end if
         if (value > max_value) then
            max_value = value
            max_rank = rank_value
         end if
      end do
      avg_value = sum_value/real(nprocs, wp)
      imbalance = compute_openmp_imbalance(max_value, avg_value)
   end subroutine set_mpi_openmp_rank_metric

   real(wp) function bounded_openmp_call_count_average(sum_delta, count, min_count, max_count) result(avg)
      real(wp), intent(in) :: sum_delta
      integer, intent(in) :: count
      integer(int64), intent(in) :: min_count
      integer(int64), intent(in) :: max_count

      if (count <= 0) then
         avg = 0.0_wp
         return
      end if
      avg = real(min_count, wp) + sum_delta/real(count, wp)
      avg = max(avg, real(min_count, wp))
      avg = min(avg, real(max_count, wp))
   end function bounded_openmp_call_count_average

   subroutine resolve_mpi_openmp_datatypes(mpi_wp_type, mpi_int64_type, status, diagnostic)
#ifdef FTIMER_USE_MPI
      type(MPI_Datatype), intent(out) :: mpi_wp_type
      type(MPI_Datatype), intent(out) :: mpi_int64_type
#else
      integer, intent(out) :: mpi_wp_type
      integer, intent(out) :: mpi_int64_type
#endif
      integer, intent(out) :: status
      character(len=*), intent(out) :: diagnostic
#ifdef FTIMER_USE_MPI
      logical :: cleanup_ok
      integer :: int64_size
      integer :: mpierr
      integer :: type_size
      type(MPI_Errhandler) :: saved_errhandler
      integer :: wp_size

      diagnostic = ''
      cleanup_ok = .true.
      wp_size = storage_size(1.0_wp)/8
      int64_size = storage_size(0_int64)/8
      if ((8*wp_size /= storage_size(1.0_wp)) .or. (8*int64_size /= storage_size(0_int64))) then
         status = FTIMER_ERR_UNKNOWN
         diagnostic = &
            "ftimer_openmp mpi_openmp_summary could not map real(wp) or integer(int64) to whole bytes"
         return
      end if

      call MPI_Comm_get_errhandler(MPI_COMM_SELF, saved_errhandler, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         diagnostic = &
            "ftimer_openmp mpi_openmp_summary could not inspect MPI_COMM_SELF error handler"
         return
      end if

      call MPI_Comm_set_errhandler(MPI_COMM_SELF, MPI_ERRORS_RETURN, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         diagnostic = &
            "ftimer_openmp mpi_openmp_summary could not enable MPI error returns before datatype validation"
         call free_mpi_openmp_errhandler(saved_errhandler, cleanup_ok, diagnostic)
         return
      end if

      call MPI_Type_match_size(MPI_TYPECLASS_REAL, wp_size, mpi_wp_type, mpierr)
      if ((mpierr /= MPI_SUCCESS) .or. (mpi_wp_type%MPI_VAL == MPI_DATATYPE_NULL%MPI_VAL)) then
         status = FTIMER_ERR_UNKNOWN
         diagnostic = "ftimer_openmp mpi_openmp_summary could not find an MPI real datatype matching real(wp)"
         call restore_mpi_openmp_comm_self_errhandler(saved_errhandler, cleanup_ok, diagnostic)
         return
      end if
      call MPI_Type_size(mpi_wp_type, type_size, mpierr)
      if ((mpierr /= MPI_SUCCESS) .or. (type_size /= wp_size)) then
         status = FTIMER_ERR_UNKNOWN
         diagnostic = "ftimer_openmp mpi_openmp_summary MPI real datatype size does not match real(wp)"
         call restore_mpi_openmp_comm_self_errhandler(saved_errhandler, cleanup_ok, diagnostic)
         return
      end if
      call MPI_Type_match_size(MPI_TYPECLASS_INTEGER, int64_size, mpi_int64_type, mpierr)
      if ((mpierr /= MPI_SUCCESS) .or. (mpi_int64_type%MPI_VAL == MPI_DATATYPE_NULL%MPI_VAL)) then
         status = FTIMER_ERR_UNKNOWN
         diagnostic = "ftimer_openmp mpi_openmp_summary could not find an MPI integer datatype matching integer(int64)"
         call restore_mpi_openmp_comm_self_errhandler(saved_errhandler, cleanup_ok, diagnostic)
         return
      end if
      call MPI_Type_size(mpi_int64_type, type_size, mpierr)
      if ((mpierr /= MPI_SUCCESS) .or. (type_size /= int64_size)) then
         status = FTIMER_ERR_UNKNOWN
         diagnostic = "ftimer_openmp mpi_openmp_summary MPI integer datatype size does not match integer(int64)"
         call restore_mpi_openmp_comm_self_errhandler(saved_errhandler, cleanup_ok, diagnostic)
         return
      end if

      call restore_mpi_openmp_comm_self_errhandler(saved_errhandler, cleanup_ok, diagnostic)
      if (.not. cleanup_ok) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      status = FTIMER_SUCCESS
#else
      mpi_wp_type = -1
      mpi_int64_type = -1
      diagnostic = ''
      status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   end subroutine resolve_mpi_openmp_datatypes

#ifdef FTIMER_USE_MPI
   subroutine restore_mpi_openmp_comm_self_errhandler(saved_errhandler, cleanup_ok, diagnostic)
      type(MPI_Errhandler), intent(inout) :: saved_errhandler
      logical, intent(out) :: cleanup_ok
      character(len=*), intent(inout) :: diagnostic
      character(len=256) :: original_diagnostic
      integer :: mpierr

      cleanup_ok = .true.
      original_diagnostic = diagnostic
      call MPI_Comm_set_errhandler(MPI_COMM_SELF, saved_errhandler, mpierr)
      if (mpierr /= MPI_SUCCESS) cleanup_ok = .false.
      if (mpierr /= MPI_SUCCESS) &
         call append_mpi_openmp_datatype_diagnostic(original_diagnostic, &
                                                    "could not restore MPI_COMM_SELF error handler", &
                                                    diagnostic)
      call free_mpi_openmp_errhandler(saved_errhandler, cleanup_ok, diagnostic)
   end subroutine restore_mpi_openmp_comm_self_errhandler

   subroutine free_mpi_openmp_errhandler(errhandler, cleanup_ok, diagnostic)
      type(MPI_Errhandler), intent(inout) :: errhandler
      logical, intent(inout) :: cleanup_ok
      character(len=*), intent(inout) :: diagnostic
      character(len=256) :: original_diagnostic
      integer :: mpierr

      original_diagnostic = diagnostic
      call MPI_Errhandler_free(errhandler, mpierr)
      if (mpierr /= MPI_SUCCESS) cleanup_ok = .false.
      if (mpierr /= MPI_SUCCESS) &
         call append_mpi_openmp_datatype_diagnostic(original_diagnostic, &
                                                    "could not free saved MPI error handler", &
                                                    diagnostic)
   end subroutine free_mpi_openmp_errhandler

   subroutine append_mpi_openmp_datatype_diagnostic(original_diagnostic, cleanup_diagnostic, diagnostic)
      character(len=*), intent(in) :: original_diagnostic
      character(len=*), intent(in) :: cleanup_diagnostic
      character(len=*), intent(inout) :: diagnostic

      if (len_trim(original_diagnostic) > 0) then
         diagnostic = trim(original_diagnostic)//"; also "//trim(cleanup_diagnostic)
      else
         diagnostic = "ftimer_openmp mpi_openmp_summary "//trim(cleanup_diagnostic)
      end if
   end subroutine append_mpi_openmp_datatype_diagnostic
#endif

   subroutine format_mpi_openmp_mismatch_diagnostic(mismatch_flags, reason, diagnostic)
      integer, intent(in) :: mismatch_flags(:)
      character(len=*), intent(in) :: reason
      character(len=*), intent(out) :: diagnostic
      character(len=*), parameter :: base_message = &
                                     "ftimer_openmp mpi_openmp_summary detected inconsistent strict hybrid descriptors"
      character(len=*), parameter :: rank_prefix = "; disagreeing ranks "
      character(len=32) :: rank_text
      character(len=len(diagnostic)) :: rank_list
      integer :: available_len
      integer :: i

      diagnostic = trim(base_message)//" ("//trim(reason)//")"
      rank_list = ''
      available_len = len(diagnostic) - len_trim(diagnostic) - len(rank_prefix)
      if (available_len <= 0) return

      do i = 1, size(mismatch_flags)
         if (mismatch_flags(i) == 0) cycle
         write (rank_text, '(i0)') i - 1
         if (len_trim(rank_list) <= 0) then
            if (len_trim(rank_text) <= available_len) rank_list = trim(rank_text)
         else
            if (len_trim(rank_list) + 2 + len_trim(rank_text) <= available_len) then
               rank_list = trim(rank_list)//", "//trim(rank_text)
            end if
         end if
      end do

      if (len_trim(rank_list) > 0) diagnostic = trim(diagnostic)//rank_prefix//trim(rank_list)
   end subroutine format_mpi_openmp_mismatch_diagnostic

   subroutine format_mpi_openmp_summary(summary, text, metadata)
      type(ftimer_mpi_openmp_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      type(openmp_report_buffer_t) :: buffer
      character(len=:), allocatable :: display
      character(len=:), allocatable :: line
      integer :: i
      integer :: key_width
      integer :: line_width
      integer :: name_width

      call init_openmp_report_buffer(buffer, default_report_buffer_capacity)
      call append_openmp_line(buffer, 'MPI+OpenMP summary')

      key_width = openmp_metadata_key_width(metadata)
      key_width = max(key_width, len('Ranks'))
      key_width = max(key_width, len('Rank summary window min/avg/max (s)'))
      key_width = max(key_width, len('Rank timed-region envelope min/avg/max (s)'))
      key_width = max(key_width, len('Rank summed lane root work min/avg/max (s)'))
      key_width = max(key_width, len('Rank summed lane self work min/avg/max (s)'))

      call append_openmp_integer_metric(buffer, 'Ranks', key_width, summary%num_ranks)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank summary window min/avg/max (s)', key_width, &
                                                 summary%min_rank_summary_window_time, &
                                                 summary%avg_rank_summary_window_time, &
                                                 summary%max_rank_summary_window_time)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank timed-region envelope min/avg/max (s)', key_width, &
                                                 summary%min_rank_timed_region_envelope_time, &
                                                 summary%avg_rank_timed_region_envelope_time, &
                                                 summary%max_rank_timed_region_envelope_time)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank summed lane root work min/avg/max (s)', key_width, &
                                                 summary%min_rank_sum_lane_root_inclusive_time, &
                                                 summary%avg_rank_sum_lane_root_inclusive_time, &
                                                 summary%max_rank_sum_lane_root_inclusive_time)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank summed lane self work min/avg/max (s)', key_width, &
                                                 summary%min_rank_sum_lane_self_time, &
                                                 summary%avg_rank_sum_lane_self_time, &
                                                 summary%max_rank_sum_lane_self_time)
      if (present(metadata)) then
         do i = 1, size(metadata)
            if (openmp_metadata_key_len(metadata(i)) <= 0) cycle
            call append_openmp_text_metric(buffer, openmp_metadata_key_text(metadata(i)), key_width, &
                                           openmp_metadata_value_text(metadata(i)))
         end do
      end if

      call append_openmp_line(buffer, '')
      call append_openmp_line(buffer, &
                              'Report note: strict hybrid reductions require every rank and eligible lane to match.')
      call append_openmp_line(buffer, 'Report note: Rank/lane samples are not zero-filled.')
      call append_openmp_line(buffer, '')
      call append_openmp_line(buffer, 'Rank details')
      call append_openmp_line(buffer, &
                              'Rank  Lanes  Window (s)  Rank timed-region envelope (s)  Lane root work (s)  Lane self work (s)')
      do i = 1, size(summary%ranks)
         allocate (character(len=160) :: line)
         write (line, '(i4,2x,i5,2x,f10.6,2x,f32.6,2x,f18.6,2x,f18.6)') &
            summary%ranks(i)%rank, summary%ranks(i)%observed_participating_lane_count, &
            summary%ranks(i)%summary_window_time, summary%ranks(i)%timed_region_envelope_time, &
            summary%ranks(i)%sum_lane_root_inclusive_time, summary%ranks(i)%sum_lane_self_time
         call append_openmp_line(buffer, trim(line))
         deallocate (line)
      end do

      call append_openmp_line(buffer, '')
      name_width = mpi_openmp_summary_name_width(summary)
      line_width = name_width + 230
      allocate (character(len=line_width) :: line)
      write (line, '(a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a)') &
         padded_openmp_text('Timer name', name_width), 'Domain', 'Ranks', 'Rank/lane samples', &
         'Missing', 'Sum Incl (s)', 'Sum Self (s)', 'Min Incl (s)', 'Avg Incl (s)', &
         'Max Incl (s)', 'Avg Calls'
      call append_openmp_line(buffer, trim(line))
      call append_openmp_line(buffer, repeat('-', len_trim(line)))

      do i = 1, summary%num_entries
         display = repeat(' ', 2*summary%entries(i)%depth)//mpi_openmp_entry_name(summary%entries(i))
         write (line, '(a,2x,a,2x,i5,2x,i17,2x,i7,2x,f12.6,2x,f12.6,2x,f12.6,2x,f12.6,2x,f12.6,2x,f9.3)') &
            padded_openmp_text(display, name_width), mpi_openmp_entry_domain(summary%entries(i)), &
            summary%entries(i)%participating_rank_count, &
            summary%entries(i)%participating_rank_lane_sample_count, &
            summary%entries(i)%missing_rank_lane_sample_count, &
            summary%entries(i)%sum_participating_lane_inclusive_time, &
            summary%entries(i)%sum_participating_lane_self_time, &
            summary%entries(i)%min_participating_lane_inclusive_time, &
            summary%entries(i)%avg_participating_lane_inclusive_time, &
            summary%entries(i)%max_participating_lane_inclusive_time, &
            summary%entries(i)%avg_participating_lane_call_count
         call append_openmp_line(buffer, trim(line))
      end do

      call finish_openmp_report_buffer(buffer, text)
   end subroutine format_mpi_openmp_summary

   subroutine append_mpi_openmp_real_triplet_metric(buffer, label, key_width, min_value, avg_value, max_value)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: label
      integer, intent(in) :: key_width
      real(wp), intent(in) :: min_value
      real(wp), intent(in) :: avg_value
      real(wp), intent(in) :: max_value
      character(len=160) :: value_text

      write (value_text, '(f0.6," / ",f0.6," / ",f0.6)') min_value, avg_value, max_value
      call append_openmp_text_metric(buffer, label, key_width, trim(value_text))
   end subroutine append_mpi_openmp_real_triplet_metric

   integer function mpi_openmp_summary_name_width(summary) result(width)
      type(ftimer_mpi_openmp_summary_t), intent(in) :: summary
      integer :: i

      width = len('Timer name')
      do i = 1, summary%num_entries
         width = max(width, 2*summary%entries(i)%depth + len(mpi_openmp_entry_name(summary%entries(i))))
      end do
   end function mpi_openmp_summary_name_width

   function mpi_openmp_entry_name(entry) result(name)
      type(ftimer_mpi_openmp_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name

      if (allocated(entry%name)) then
         name = entry%name
      else
         name = ''
      end if
   end function mpi_openmp_entry_name

   function mpi_openmp_entry_domain(entry) result(domain)
      type(ftimer_mpi_openmp_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: domain

      if (allocated(entry%execution_domain)) then
         domain = entry%execution_domain
      else
         domain = ''
      end if
   end function mpi_openmp_entry_domain

   subroutine format_mpi_openmp_summary_csv(summary, text, metadata, include_header)
      type(ftimer_mpi_openmp_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      logical, intent(in), optional :: include_header
      type(openmp_report_buffer_t) :: buffer
      integer :: i
      logical :: emit_header

      call init_openmp_report_buffer(buffer, default_report_buffer_capacity)
      emit_header = .true.
      if (present(include_header)) emit_header = include_header
      if (emit_header) call append_openmp_line(buffer, mpi_openmp_csv_header_line())
      call append_mpi_openmp_summary_csv_record(buffer, summary)
      if (present(metadata)) then
         do i = 1, size(metadata)
            if (openmp_metadata_key_len(metadata(i)) <= 0) cycle
            call append_mpi_openmp_metadata_csv_record(buffer, metadata(i))
         end do
      end if
      do i = 1, size(summary%ranks)
         call append_mpi_openmp_rank_csv_record(buffer, summary%ranks(i))
      end do
      do i = 1, summary%num_entries
         call append_mpi_openmp_entry_csv_record(buffer, summary%entries(i))
      end do
      call finish_openmp_report_buffer(buffer, text)
   end subroutine format_mpi_openmp_summary_csv

   subroutine append_mpi_openmp_summary_csv_record(buffer, summary)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_openmp_summary_t), intent(in) :: summary
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_csv_row(row, 'summary')
      call append_empty_openmp_csv_fields(row, 2)
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%num_ranks))
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%num_entries))
      call append_empty_openmp_csv_fields(row, 7)
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_summary_window_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_timed_region_envelope_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_sum_lane_root_inclusive_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_sum_lane_self_imbalance))
      call append_empty_openmp_csv_fields(row, 28)
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_summary_csv_record

   subroutine append_mpi_openmp_metadata_csv_record(buffer, item)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_metadata_t), intent(in) :: item
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_csv_row(row, 'metadata')
      call append_openmp_csv_field(row, openmp_metadata_key_text(item))
      call append_openmp_csv_field(row, openmp_metadata_value_text(item))
      call append_empty_openmp_csv_fields(row, 53)
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_metadata_csv_record

   subroutine append_mpi_openmp_rank_csv_record(buffer, rank_entry)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_openmp_rank_t), intent(in) :: rank_entry
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_csv_row(row, 'rank')
      call append_empty_openmp_csv_fields(row, 4)
      call append_openmp_csv_field(row, openmp_integer_csv_text(rank_entry%rank))
      call append_openmp_csv_field(row, openmp_integer_csv_text(rank_entry%configured_lane_capacity))
      call append_openmp_csv_field(row, openmp_integer_csv_text(rank_entry%observed_participating_lane_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%sum_lane_self_time))
      call append_empty_openmp_csv_fields(row, 44)
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_rank_csv_record

   subroutine append_mpi_openmp_entry_csv_record(buffer, entry)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_openmp_summary_entry_t), intent(in) :: entry
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_csv_row(row, 'entry')
      call append_empty_openmp_csv_fields(row, 27)
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%node_id))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%parent_id))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%depth))
      call append_openmp_csv_field(row, mpi_openmp_entry_name(entry))
      call append_openmp_csv_field(row, mpi_openmp_entry_domain(entry))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%participating_rank_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%missing_rank_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%eligible_rank_lane_sample_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%participating_rank_lane_sample_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%missing_rank_lane_sample_count))
      call append_openmp_csv_field(row, openmp_logical_csv_text(entry%missing_rank_lane_sample_count_known))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%sum_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%sum_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%participating_lane_inclusive_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%participating_lane_self_imbalance))
      call append_openmp_csv_field(row, openmp_int64_csv_text(entry%min_participating_lane_call_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_call_count))
      call append_openmp_csv_field(row, openmp_int64_csv_text(entry%max_participating_lane_call_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_participating_lane_pct_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_pct_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_participating_lane_pct_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%participating_lane_pct_imbalance))
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_entry_csv_record

   subroutine begin_mpi_openmp_csv_row(row, record_type)
      type(openmp_report_buffer_t), intent(out) :: row
      character(len=*), intent(in) :: record_type

      call init_openmp_report_buffer(row, 512)
      call append_openmp_csv_field(row, FTIMER_MPI_OPENMP_CSV_FORMAT_VERSION)
      call append_openmp_csv_field(row, 'mpi_openmp')
      call append_openmp_csv_field(row, record_type)
   end subroutine begin_mpi_openmp_csv_row

   function mpi_openmp_csv_header_line() result(line)
      character(len=:), allocatable :: line
      type(openmp_report_buffer_t) :: row

      call init_openmp_report_buffer(row, 2048)
      call append_openmp_csv_field(row, 'format_version')
      call append_openmp_csv_field(row, 'summary_kind')
      call append_openmp_csv_field(row, 'record_type')
      call append_openmp_csv_field(row, 'key')
      call append_openmp_csv_field(row, 'value')
      call append_openmp_csv_field(row, 'num_ranks')
      call append_openmp_csv_field(row, 'num_entries')
      call append_openmp_csv_field(row, 'rank')
      call append_openmp_csv_field(row, 'configured_lane_capacity')
      call append_openmp_csv_field(row, 'observed_participating_lane_count')
      call append_openmp_csv_field(row, 'summary_window_time')
      call append_openmp_csv_field(row, 'timed_region_envelope_time')
      call append_openmp_csv_field(row, 'sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'sum_lane_self_time')
      call append_openmp_csv_field(row, 'min_rank_summary_window_time')
      call append_openmp_csv_field(row, 'avg_rank_summary_window_time')
      call append_openmp_csv_field(row, 'max_rank_summary_window_time')
      call append_openmp_csv_field(row, 'rank_summary_window_imbalance')
      call append_openmp_csv_field(row, 'min_rank_timed_region_envelope_time')
      call append_openmp_csv_field(row, 'avg_rank_timed_region_envelope_time')
      call append_openmp_csv_field(row, 'max_rank_timed_region_envelope_time')
      call append_openmp_csv_field(row, 'rank_timed_region_envelope_imbalance')
      call append_openmp_csv_field(row, 'min_rank_sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'avg_rank_sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'max_rank_sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'rank_sum_lane_root_inclusive_imbalance')
      call append_openmp_csv_field(row, 'min_rank_sum_lane_self_time')
      call append_openmp_csv_field(row, 'avg_rank_sum_lane_self_time')
      call append_openmp_csv_field(row, 'max_rank_sum_lane_self_time')
      call append_openmp_csv_field(row, 'rank_sum_lane_self_imbalance')
      call append_openmp_csv_field(row, 'node_id')
      call append_openmp_csv_field(row, 'parent_id')
      call append_openmp_csv_field(row, 'depth')
      call append_openmp_csv_field(row, 'name')
      call append_openmp_csv_field(row, 'execution_domain')
      call append_openmp_csv_field(row, 'participating_rank_count')
      call append_openmp_csv_field(row, 'missing_rank_count')
      call append_openmp_csv_field(row, 'eligible_rank_lane_sample_count')
      call append_openmp_csv_field(row, 'participating_rank_lane_sample_count')
      call append_openmp_csv_field(row, 'missing_rank_lane_sample_count')
      call append_openmp_csv_field(row, 'missing_rank_lane_sample_count_known')
      call append_openmp_csv_field(row, 'sum_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'sum_participating_lane_self_time')
      call append_openmp_csv_field(row, 'min_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'avg_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'max_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'participating_lane_inclusive_imbalance')
      call append_openmp_csv_field(row, 'min_participating_lane_self_time')
      call append_openmp_csv_field(row, 'avg_participating_lane_self_time')
      call append_openmp_csv_field(row, 'max_participating_lane_self_time')
      call append_openmp_csv_field(row, 'participating_lane_self_imbalance')
      call append_openmp_csv_field(row, 'min_participating_lane_call_count')
      call append_openmp_csv_field(row, 'avg_participating_lane_call_count')
      call append_openmp_csv_field(row, 'max_participating_lane_call_count')
      call append_openmp_csv_field(row, 'min_participating_lane_pct_time')
      call append_openmp_csv_field(row, 'avg_participating_lane_pct_time')
      call append_openmp_csv_field(row, 'max_participating_lane_pct_time')
      call append_openmp_csv_field(row, 'participating_lane_pct_imbalance')
      call finish_openmp_report_buffer(row, line)
   end function mpi_openmp_csv_header_line

   subroutine get_mpi_openmp_csv_header_mode(filename, append_mode, include_header, status, iomsg)
      character(len=*), intent(in) :: filename
      logical, intent(in) :: append_mode
      logical, intent(out) :: include_header
      integer, intent(out) :: status
      character(len=*), intent(out) :: iomsg
      character(len=1) :: ch
      character(len=:), allocatable :: expected_header
      character(len=:), allocatable :: header_line
      character(len=:), allocatable :: record_text
      character(len=1) :: last_char
      integer :: expected_field_count
      integer :: io
      integer :: record_field_count
      integer :: record_prefix_limit
      integer :: unit
      logical :: exists
      logical :: after_quoted_field
      logical :: field_has_content
      logical :: in_quotes
      logical :: pending_record_cr
      logical :: pending_quote
      logical :: reading_header
      logical :: saw_any_char

      include_header = .true.
      status = FTIMER_SUCCESS
      iomsg = ''
      if (.not. append_mode) return

      inquire (file=filename, exist=exists)
      if (.not. exists) return

      expected_header = mpi_openmp_csv_header_line()
      expected_field_count = openmp_csv_field_count(expected_header)
      header_line = ''
      record_text = ''
      record_prefix_limit = 64
      record_field_count = 1
      last_char = ''
      reading_header = .true.
      after_quoted_field = .false.
      field_has_content = .false.
      in_quotes = .false.
      pending_record_cr = .false.
      pending_quote = .false.
      saw_any_char = .false.

      open (newunit=unit, file=filename, status='old', access='stream', form='unformatted', &
            action='read', iostat=io, iomsg=iomsg)
      if (io /= 0) then
         status = FTIMER_ERR_IO
         return
      end if

      do
         read (unit, iostat=io, iomsg=iomsg) ch
         if (io == iostat_end) exit
         if (io /= 0) then
            close (unit)
            status = FTIMER_ERR_IO
            return
         end if

         last_char = ch
         saw_any_char = .true.

         if (reading_header) then
            if (ch == new_line('a')) then
               reading_header = .false.
               call strip_openmp_trailing_carriage_return(header_line)
               if ((len(header_line) /= len(expected_header)) .or. (header_line /= expected_header)) then
                  close (unit)
                  status = FTIMER_ERR_IO
                  iomsg = 'existing MPI+OpenMP summary CSV header does not match format version 1'
                  return
               end if
            else
               header_line = header_line//ch
               if (len(header_line) > len(expected_header) + 1) then
                  close (unit)
                  status = FTIMER_ERR_IO
                  iomsg = 'existing MPI+OpenMP summary CSV header does not match format version 1'
                  return
               end if
            end if
            cycle
         end if

         if (pending_record_cr) then
            if (ch /= new_line('a')) then
               close (unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing MPI+OpenMP summary CSV records contain a bare carriage return'
               return
            end if
            pending_record_cr = .false.
         end if

         if (pending_quote) then
            if (ch == '"') then
               pending_quote = .false.
               call append_limited_openmp_csv_record_prefix(record_text, ch, record_prefix_limit)
               cycle
            end if
            in_quotes = .false.
            pending_quote = .false.
            after_quoted_field = .true.
         end if

         if ((ch == achar(13)) .and. (.not. in_quotes)) then
            pending_record_cr = .true.
            cycle
         end if

         if (after_quoted_field) then
            if ((ch /= ',') .and. (ch /= new_line('a'))) then
               close (unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing MPI+OpenMP summary CSV records contain malformed quoted fields'
               return
            end if
         end if

         if ((ch == new_line('a')) .and. (.not. in_quotes)) then
            call strip_openmp_trailing_carriage_return(record_text)
            if ((record_field_count /= expected_field_count) .or. &
                (.not. mpi_openmp_csv_record_has_valid_prefix(record_text))) then
               close (unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing MPI+OpenMP summary CSV records do not match format version 1'
               return
            end if
            record_text = ''
            record_field_count = 1
            after_quoted_field = .false.
            field_has_content = .false.
            cycle
         end if

         call append_limited_openmp_csv_record_prefix(record_text, ch, record_prefix_limit)

         if ((ch == ',') .and. (.not. in_quotes)) then
            record_field_count = record_field_count + 1
            if (after_quoted_field) after_quoted_field = .false.
            field_has_content = .false.
            cycle
         end if

         if (ch == '"') then
            if (in_quotes) then
               pending_quote = .true.
            else if (field_has_content) then
               close (unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing MPI+OpenMP summary CSV records contain malformed quoted fields'
               return
            else
               in_quotes = .true.
               after_quoted_field = .false.
            end if
         else if (.not. in_quotes) then
            field_has_content = .true.
         end if
      end do
      close (unit)

      if (.not. saw_any_char) return

      if (last_char /= new_line('a')) then
         status = FTIMER_ERR_IO
         iomsg = 'existing MPI+OpenMP summary CSV append target does not end with a newline'
         return
      end if

      if (in_quotes) then
         status = FTIMER_ERR_IO
         iomsg = 'existing MPI+OpenMP summary CSV records contain an unterminated quoted field'
         return
      end if

      if (pending_record_cr) then
         status = FTIMER_ERR_IO
         iomsg = 'existing MPI+OpenMP summary CSV records contain a bare carriage return'
         return
      end if

      include_header = .false.
   end subroutine get_mpi_openmp_csv_header_mode

   logical function mpi_openmp_csv_record_has_valid_prefix(line) result(matches)
      character(len=*), intent(in) :: line

      matches = openmp_starts_with(line, '"'//FTIMER_MPI_OPENMP_CSV_FORMAT_VERSION// &
                                   '","mpi_openmp","summary",') .or. &
                openmp_starts_with(line, '"'//FTIMER_MPI_OPENMP_CSV_FORMAT_VERSION// &
                                   '","mpi_openmp","metadata",') .or. &
                openmp_starts_with(line, '"'//FTIMER_MPI_OPENMP_CSV_FORMAT_VERSION// &
                                   '","mpi_openmp","rank",') .or. &
                openmp_starts_with(line, '"'//FTIMER_MPI_OPENMP_CSV_FORMAT_VERSION// &
                                   '","mpi_openmp","entry",')
   end function mpi_openmp_csv_record_has_valid_prefix

   subroutine format_mpi_openmp_union_summary(summary, text, metadata)
      type(ftimer_mpi_openmp_union_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      type(openmp_report_buffer_t) :: buffer
      character(len=:), allocatable :: display
      character(len=:), allocatable :: line
      integer :: i
      integer :: key_width
      integer :: line_width
      integer :: name_width

      call init_openmp_report_buffer(buffer, default_report_buffer_capacity)
      call append_openmp_line(buffer, 'Sparse MPI+OpenMP union summary')

      key_width = openmp_metadata_key_width(metadata)
      key_width = max(key_width, len('Ranks'))
      key_width = max(key_width, len('Rank summary window min/avg/max (s)'))
      key_width = max(key_width, len('Rank timed-region envelope min/avg/max (s)'))
      key_width = max(key_width, len('Rank summed lane root work min/avg/max (s)'))
      key_width = max(key_width, len('Rank summed lane self work min/avg/max (s)'))

      call append_openmp_integer_metric(buffer, 'Ranks', key_width, summary%num_ranks)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank summary window min/avg/max (s)', key_width, &
                                                 summary%min_rank_summary_window_time, &
                                                 summary%avg_rank_summary_window_time, &
                                                 summary%max_rank_summary_window_time)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank timed-region envelope min/avg/max (s)', key_width, &
                                                 summary%min_rank_timed_region_envelope_time, &
                                                 summary%avg_rank_timed_region_envelope_time, &
                                                 summary%max_rank_timed_region_envelope_time)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank summed lane root work min/avg/max (s)', key_width, &
                                                 summary%min_rank_sum_lane_root_inclusive_time, &
                                                 summary%avg_rank_sum_lane_root_inclusive_time, &
                                                 summary%max_rank_sum_lane_root_inclusive_time)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank summed lane self work min/avg/max (s)', key_width, &
                                                 summary%min_rank_sum_lane_self_time, &
                                                 summary%avg_rank_sum_lane_self_time, &
                                                 summary%max_rank_sum_lane_self_time)
      if (present(metadata)) then
         do i = 1, size(metadata)
            if (openmp_metadata_key_len(metadata(i)) <= 0) cycle
            call append_openmp_text_metric(buffer, openmp_metadata_key_text(metadata(i)), key_width, &
                                           openmp_metadata_value_text(metadata(i)))
         end do
      end if

      call append_openmp_line(buffer, '')
      call append_openmp_line(buffer, &
                              'Report note: sparse union reductions preserve missing ranks and missing lane samples.')
      call append_openmp_line(buffer, 'Report note: Rank/lane samples are not zero-filled.')
      call append_openmp_line(buffer, '')
      call append_openmp_line(buffer, 'Rank details')
      call append_openmp_line(buffer, &
                              'Rank  Lanes  Window (s)  Rank timed-region envelope (s)  Lane root work (s)  Lane self work (s)')
      do i = 1, size(summary%ranks)
         allocate (character(len=160) :: line)
         write (line, '(i4,2x,i5,2x,f10.6,2x,f32.6,2x,f18.6,2x,f18.6)') &
            summary%ranks(i)%rank, summary%ranks(i)%observed_participating_lane_count, &
            summary%ranks(i)%summary_window_time, summary%ranks(i)%timed_region_envelope_time, &
            summary%ranks(i)%sum_lane_root_inclusive_time, summary%ranks(i)%sum_lane_self_time
         call append_openmp_line(buffer, trim(line))
         deallocate (line)
      end do

      call append_openmp_line(buffer, '')
      name_width = mpi_openmp_union_summary_name_width(summary)
      line_width = name_width + 260
      allocate (character(len=line_width) :: line)
      write (line, '(a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a)') &
         padded_openmp_text('Timer name', name_width), 'Domain', 'Ranks', 'Missing ranks', &
         'Rank/lane samples', 'Missing samples', 'Sum Incl (s)', 'Sum Self (s)', &
         'Min Incl (s)', 'Avg Incl (s)', 'Max Incl (s)', 'Avg Calls'
      call append_openmp_line(buffer, trim(line))
      call append_openmp_line(buffer, repeat('-', len_trim(line)))

      do i = 1, summary%num_entries
         display = repeat(' ', 2*summary%entries(i)%depth)//mpi_openmp_union_entry_name(summary%entries(i))
         write (line, '(a,2x,a,2x,i5,2x,i13,2x,i17,2x,i15,2x,f12.6,2x,f12.6,2x,f12.6,2x,f12.6,2x,f12.6,2x,f9.3)') &
            padded_openmp_text(display, name_width), mpi_openmp_union_entry_domain(summary%entries(i)), &
            summary%entries(i)%participating_rank_count, summary%entries(i)%missing_rank_count, &
            summary%entries(i)%participating_rank_lane_sample_count, &
            summary%entries(i)%missing_rank_lane_sample_count, &
            summary%entries(i)%sum_participating_lane_inclusive_time, &
            summary%entries(i)%sum_participating_lane_self_time, &
            summary%entries(i)%min_participating_lane_inclusive_time, &
            summary%entries(i)%avg_participating_lane_inclusive_time, &
            summary%entries(i)%max_participating_lane_inclusive_time, &
            summary%entries(i)%avg_participating_lane_call_count
         call append_openmp_line(buffer, trim(line))
      end do

      call finish_openmp_report_buffer(buffer, text)
   end subroutine format_mpi_openmp_union_summary

   integer function mpi_openmp_union_summary_name_width(summary) result(width)
      type(ftimer_mpi_openmp_union_summary_t), intent(in) :: summary
      integer :: i

      width = len('Timer name')
      do i = 1, summary%num_entries
         width = max(width, 2*summary%entries(i)%depth + len(mpi_openmp_union_entry_name(summary%entries(i))))
      end do
   end function mpi_openmp_union_summary_name_width

   function mpi_openmp_union_entry_name(entry) result(name)
      type(ftimer_mpi_openmp_union_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name

      if (allocated(entry%name)) then
         name = entry%name
      else
         name = ''
      end if
   end function mpi_openmp_union_entry_name

   function mpi_openmp_union_entry_domain(entry) result(domain)
      type(ftimer_mpi_openmp_union_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: domain

      if (allocated(entry%execution_domain)) then
         domain = entry%execution_domain
      else
         domain = ''
      end if
   end function mpi_openmp_union_entry_domain

   subroutine format_mpi_openmp_union_summary_csv(summary, text, metadata, include_header)
      type(ftimer_mpi_openmp_union_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      logical, intent(in), optional :: include_header
      type(openmp_report_buffer_t) :: buffer
      integer :: i
      logical :: emit_header

      call init_openmp_report_buffer(buffer, default_report_buffer_capacity)
      emit_header = .true.
      if (present(include_header)) emit_header = include_header
      if (emit_header) call append_openmp_line(buffer, mpi_openmp_union_csv_header_line())
      call append_mpi_openmp_union_summary_csv_record(buffer, summary)
      if (present(metadata)) then
         do i = 1, size(metadata)
            if (openmp_metadata_key_len(metadata(i)) <= 0) cycle
            call append_mpi_openmp_union_metadata_csv_record(buffer, metadata(i))
         end do
      end if
      do i = 1, size(summary%ranks)
         call append_mpi_openmp_union_rank_csv_record(buffer, summary%ranks(i))
      end do
      do i = 1, summary%num_entries
         call append_mpi_openmp_union_entry_csv_record(buffer, summary%entries(i))
      end do
      call finish_openmp_report_buffer(buffer, text)
   end subroutine format_mpi_openmp_union_summary_csv

   subroutine append_mpi_openmp_union_summary_csv_record(buffer, summary)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_openmp_union_summary_t), intent(in) :: summary
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_union_csv_row(row, 'summary')
      call append_empty_openmp_csv_fields(row, 2)
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%num_ranks))
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%num_entries))
      call append_empty_openmp_csv_fields(row, 7)
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_summary_window_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_timed_region_envelope_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_sum_lane_root_inclusive_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_sum_lane_self_imbalance))
      call append_empty_openmp_csv_fields(row, 28)
      call append_openmp_csv_field(row, 'sparse_union')
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_union_summary_csv_record

   subroutine append_mpi_openmp_union_metadata_csv_record(buffer, item)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_metadata_t), intent(in) :: item
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_union_csv_row(row, 'metadata')
      call append_openmp_csv_field(row, openmp_metadata_key_text(item))
      call append_openmp_csv_field(row, openmp_metadata_value_text(item))
      call append_empty_openmp_csv_fields(row, 53)
      call append_openmp_csv_field(row, 'sparse_union')
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_union_metadata_csv_record

   subroutine append_mpi_openmp_union_rank_csv_record(buffer, rank_entry)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_openmp_union_rank_t), intent(in) :: rank_entry
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_union_csv_row(row, 'rank')
      call append_empty_openmp_csv_fields(row, 4)
      call append_openmp_csv_field(row, openmp_integer_csv_text(rank_entry%rank))
      call append_openmp_csv_field(row, openmp_integer_csv_text(rank_entry%configured_lane_capacity))
      call append_openmp_csv_field(row, openmp_integer_csv_text(rank_entry%observed_participating_lane_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%sum_lane_self_time))
      call append_empty_openmp_csv_fields(row, 44)
      call append_openmp_csv_field(row, 'sparse_union')
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_union_rank_csv_record

   subroutine append_mpi_openmp_union_entry_csv_record(buffer, entry)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_openmp_union_summary_entry_t), intent(in) :: entry
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_union_csv_row(row, 'entry')
      call append_empty_openmp_csv_fields(row, 27)
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%node_id))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%parent_id))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%depth))
      call append_openmp_csv_field(row, mpi_openmp_union_entry_name(entry))
      call append_openmp_csv_field(row, mpi_openmp_union_entry_domain(entry))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%participating_rank_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%missing_rank_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%eligible_rank_lane_sample_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%participating_rank_lane_sample_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%missing_rank_lane_sample_count))
      call append_openmp_csv_field(row, openmp_logical_csv_text(entry%missing_rank_lane_sample_count_known))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%sum_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%sum_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%participating_lane_inclusive_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%participating_lane_self_imbalance))
      call append_openmp_csv_field(row, openmp_int64_csv_text(entry%min_participating_lane_call_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_call_count))
      call append_openmp_csv_field(row, openmp_int64_csv_text(entry%max_participating_lane_call_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_participating_lane_pct_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_pct_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_participating_lane_pct_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%participating_lane_pct_imbalance))
      call append_openmp_csv_field(row, 'sparse_union')
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_union_entry_csv_record

   subroutine begin_mpi_openmp_union_csv_row(row, record_type)
      type(openmp_report_buffer_t), intent(out) :: row
      character(len=*), intent(in) :: record_type

      call init_openmp_report_buffer(row, 512)
      call append_openmp_csv_field(row, FTIMER_MPI_OPENMP_UNION_CSV_FORMAT_VERSION)
      call append_openmp_csv_field(row, 'mpi_openmp_union')
      call append_openmp_csv_field(row, record_type)
   end subroutine begin_mpi_openmp_union_csv_row

   function mpi_openmp_union_csv_header_line() result(line)
      character(len=:), allocatable :: line
      type(openmp_report_buffer_t) :: row

      call init_openmp_report_buffer(row, 2048)
      call append_openmp_csv_field(row, 'format_version')
      call append_openmp_csv_field(row, 'summary_kind')
      call append_openmp_csv_field(row, 'record_type')
      call append_openmp_csv_field(row, 'key')
      call append_openmp_csv_field(row, 'value')
      call append_openmp_csv_field(row, 'num_ranks')
      call append_openmp_csv_field(row, 'num_entries')
      call append_openmp_csv_field(row, 'rank')
      call append_openmp_csv_field(row, 'configured_lane_capacity')
      call append_openmp_csv_field(row, 'observed_participating_lane_count')
      call append_openmp_csv_field(row, 'summary_window_time')
      call append_openmp_csv_field(row, 'timed_region_envelope_time')
      call append_openmp_csv_field(row, 'sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'sum_lane_self_time')
      call append_openmp_csv_field(row, 'min_rank_summary_window_time')
      call append_openmp_csv_field(row, 'avg_rank_summary_window_time')
      call append_openmp_csv_field(row, 'max_rank_summary_window_time')
      call append_openmp_csv_field(row, 'rank_summary_window_imbalance')
      call append_openmp_csv_field(row, 'min_rank_timed_region_envelope_time')
      call append_openmp_csv_field(row, 'avg_rank_timed_region_envelope_time')
      call append_openmp_csv_field(row, 'max_rank_timed_region_envelope_time')
      call append_openmp_csv_field(row, 'rank_timed_region_envelope_imbalance')
      call append_openmp_csv_field(row, 'min_rank_sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'avg_rank_sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'max_rank_sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'rank_sum_lane_root_inclusive_imbalance')
      call append_openmp_csv_field(row, 'min_rank_sum_lane_self_time')
      call append_openmp_csv_field(row, 'avg_rank_sum_lane_self_time')
      call append_openmp_csv_field(row, 'max_rank_sum_lane_self_time')
      call append_openmp_csv_field(row, 'rank_sum_lane_self_imbalance')
      call append_openmp_csv_field(row, 'node_id')
      call append_openmp_csv_field(row, 'parent_id')
      call append_openmp_csv_field(row, 'depth')
      call append_openmp_csv_field(row, 'name')
      call append_openmp_csv_field(row, 'execution_domain')
      call append_openmp_csv_field(row, 'participating_rank_count')
      call append_openmp_csv_field(row, 'missing_rank_count')
      call append_openmp_csv_field(row, 'eligible_rank_lane_sample_count')
      call append_openmp_csv_field(row, 'participating_rank_lane_sample_count')
      call append_openmp_csv_field(row, 'missing_rank_lane_sample_count')
      call append_openmp_csv_field(row, 'missing_rank_lane_sample_count_known')
      call append_openmp_csv_field(row, 'sum_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'sum_participating_lane_self_time')
      call append_openmp_csv_field(row, 'min_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'avg_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'max_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'participating_lane_inclusive_imbalance')
      call append_openmp_csv_field(row, 'min_participating_lane_self_time')
      call append_openmp_csv_field(row, 'avg_participating_lane_self_time')
      call append_openmp_csv_field(row, 'max_participating_lane_self_time')
      call append_openmp_csv_field(row, 'participating_lane_self_imbalance')
      call append_openmp_csv_field(row, 'min_participating_lane_call_count')
      call append_openmp_csv_field(row, 'avg_participating_lane_call_count')
      call append_openmp_csv_field(row, 'max_participating_lane_call_count')
      call append_openmp_csv_field(row, 'min_participating_lane_pct_time')
      call append_openmp_csv_field(row, 'avg_participating_lane_pct_time')
      call append_openmp_csv_field(row, 'max_participating_lane_pct_time')
      call append_openmp_csv_field(row, 'participating_lane_pct_imbalance')
      call append_openmp_csv_field(row, 'participation_policy')
      call finish_openmp_report_buffer(row, line)
   end function mpi_openmp_union_csv_header_line

   subroutine get_mpi_openmp_union_csv_header_mode(filename, append_mode, include_header, status, iomsg)
      character(len=*), intent(in) :: filename
      logical, intent(in) :: append_mode
      logical, intent(out) :: include_header
      integer, intent(out) :: status
      character(len=*), intent(out) :: iomsg
      character(len=1) :: ch
      character(len=:), allocatable :: expected_header
      character(len=:), allocatable :: header_line
      character(len=:), allocatable :: record_text
      character(len=1) :: last_char
      integer :: expected_field_count
      integer :: io
      integer :: record_field_count
      integer :: record_prefix_limit
      integer :: unit
      logical :: exists
      logical :: after_quoted_field
      logical :: field_has_content
      logical :: in_quotes
      logical :: pending_record_cr
      logical :: pending_quote
      logical :: reading_header
      logical :: saw_any_char

      include_header = .true.
      status = FTIMER_SUCCESS
      iomsg = ''
      if (.not. append_mode) return

      inquire (file=filename, exist=exists)
      if (.not. exists) return

      expected_header = mpi_openmp_union_csv_header_line()
      expected_field_count = openmp_csv_field_count(expected_header)
      header_line = ''
      record_text = ''
      record_prefix_limit = 64
      record_field_count = 1
      last_char = ''
      reading_header = .true.
      after_quoted_field = .false.
      field_has_content = .false.
      in_quotes = .false.
      pending_record_cr = .false.
      pending_quote = .false.
      saw_any_char = .false.

      open (newunit=unit, file=filename, status='old', access='stream', form='unformatted', &
            action='read', iostat=io, iomsg=iomsg)
      if (io /= 0) then
         status = FTIMER_ERR_IO
         return
      end if

      do
         read (unit, iostat=io, iomsg=iomsg) ch
         if (io == iostat_end) exit
         if (io /= 0) then
            close (unit)
            status = FTIMER_ERR_IO
            return
         end if
         last_char = ch
         saw_any_char = .true.
         if (reading_header) then
            if (ch == new_line('a')) then
               reading_header = .false.
               call strip_openmp_trailing_carriage_return(header_line)
               if ((len(header_line) /= len(expected_header)) .or. (header_line /= expected_header)) then
                  close (unit)
                  status = FTIMER_ERR_IO
                  iomsg = 'existing sparse MPI+OpenMP union summary CSV header does not match format version 1'
                  return
               end if
            else
               header_line = header_line//ch
               if (len(header_line) > len(expected_header) + 1) then
                  close (unit)
                  status = FTIMER_ERR_IO
                  iomsg = 'existing sparse MPI+OpenMP union summary CSV header does not match format version 1'
                  return
               end if
            end if
            cycle
         end if

         if (pending_record_cr) then
            if (ch /= new_line('a')) then
               close (unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing sparse MPI+OpenMP union summary CSV records contain a bare carriage return'
               return
            end if
            pending_record_cr = .false.
         end if

         if (pending_quote) then
            if (ch == '"') then
               pending_quote = .false.
               call append_limited_openmp_csv_record_prefix(record_text, ch, record_prefix_limit)
               cycle
            end if
            in_quotes = .false.
            pending_quote = .false.
            after_quoted_field = .true.
         end if

         if ((ch == achar(13)) .and. (.not. in_quotes)) then
            pending_record_cr = .true.
            cycle
         end if

         if (after_quoted_field) then
            if ((ch /= ',') .and. (ch /= new_line('a'))) then
               close (unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing sparse MPI+OpenMP union summary CSV records contain malformed quoted fields'
               return
            end if
         end if

         if ((ch == new_line('a')) .and. (.not. in_quotes)) then
            call strip_openmp_trailing_carriage_return(record_text)
            if ((record_field_count /= expected_field_count) .or. &
                (.not. mpi_openmp_union_csv_record_has_valid_prefix(record_text))) then
               close (unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing sparse MPI+OpenMP union summary CSV records do not match format version 1'
               return
            end if
            record_text = ''
            record_field_count = 1
            after_quoted_field = .false.
            field_has_content = .false.
            cycle
         end if

         call append_limited_openmp_csv_record_prefix(record_text, ch, record_prefix_limit)

         if ((ch == ',') .and. (.not. in_quotes)) then
            record_field_count = record_field_count + 1
            if (after_quoted_field) after_quoted_field = .false.
            field_has_content = .false.
            cycle
         end if

         if (ch == '"') then
            if (in_quotes) then
               pending_quote = .true.
            else if (field_has_content) then
               close (unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing sparse MPI+OpenMP union summary CSV records contain malformed quoted fields'
               return
            else
               in_quotes = .true.
               after_quoted_field = .false.
            end if
         else if (.not. in_quotes) then
            field_has_content = .true.
         end if
      end do
      close (unit)

      if (.not. saw_any_char) return

      if (last_char /= new_line('a')) then
         status = FTIMER_ERR_IO
         iomsg = 'existing sparse MPI+OpenMP union summary CSV append target does not end with a newline'
         return
      end if

      if (in_quotes) then
         status = FTIMER_ERR_IO
         iomsg = 'existing sparse MPI+OpenMP union summary CSV records contain an unterminated quoted field'
         return
      end if

      if (pending_record_cr) then
         status = FTIMER_ERR_IO
         iomsg = 'existing sparse MPI+OpenMP union summary CSV records contain a bare carriage return'
         return
      end if

      include_header = .false.
   end subroutine get_mpi_openmp_union_csv_header_mode

   logical function mpi_openmp_union_csv_record_has_valid_prefix(line) result(matches)
      character(len=*), intent(in) :: line

      matches = openmp_starts_with(line, '"'//FTIMER_MPI_OPENMP_UNION_CSV_FORMAT_VERSION// &
                                   '","mpi_openmp_union","summary",') .or. &
                openmp_starts_with(line, '"'//FTIMER_MPI_OPENMP_UNION_CSV_FORMAT_VERSION// &
                                   '","mpi_openmp_union","metadata",') .or. &
                openmp_starts_with(line, '"'//FTIMER_MPI_OPENMP_UNION_CSV_FORMAT_VERSION// &
                                   '","mpi_openmp_union","rank",') .or. &
                openmp_starts_with(line, '"'//FTIMER_MPI_OPENMP_UNION_CSV_FORMAT_VERSION// &
                                   '","mpi_openmp_union","entry",')
   end function mpi_openmp_union_csv_record_has_valid_prefix

   subroutine report_mpi_openmp_union_summary_error(self, ierr, status, diagnostic)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr
      integer, intent(in) :: status
      character(len=*), intent(in) :: diagnostic
      character(len=256) :: message

      select case (status)
      case (FTIMER_ERR_NOT_IMPLEMENTED)
         message = "ftimer_openmp mpi_openmp_union_summary requires FTIMER_USE_MPI=ON"
      case (FTIMER_ERR_ACTIVE)
         message = "ftimer_openmp mpi_openmp_union_summary requires stopped OpenMP lanes on all ranks"
      case default
         if (len_trim(diagnostic) > 0) then
            message = diagnostic
         else
            message = "ftimer_openmp mpi_openmp_union_summary MPI reduction failed"
         end if
      end select
      call report_mpi_openmp_summary_status(self, ierr, status, trim(message))
   end subroutine report_mpi_openmp_union_summary_error

   subroutine report_mpi_openmp_summary_error(self, ierr, status, diagnostic)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr
      integer, intent(in) :: status
      character(len=*), intent(in) :: diagnostic
      character(len=256) :: message

      select case (status)
      case (FTIMER_ERR_NOT_IMPLEMENTED)
         message = "ftimer_openmp mpi_openmp_summary requires FTIMER_USE_MPI=ON"
      case (FTIMER_ERR_ACTIVE)
         message = "ftimer_openmp mpi_openmp_summary requires stopped OpenMP lanes on all ranks"
      case (FTIMER_ERR_MPI_INCON)
         if (len_trim(diagnostic) > 0) then
            message = diagnostic
         else
            message = "ftimer_openmp mpi_openmp_summary detected inconsistent strict hybrid descriptors"
         end if
      case default
         if (len_trim(diagnostic) > 0) then
            message = diagnostic
         else
            message = "ftimer_openmp mpi_openmp_summary MPI reduction failed"
         end if
      end select
      call report_mpi_openmp_summary_status(self, ierr, status, trim(message))
   end subroutine report_mpi_openmp_summary_error

   subroutine report_mpi_openmp_summary_status(self, ierr, status, message)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr
      integer, intent(in) :: status
      character(len=*), intent(in) :: message

      if (present(ierr)) then
         call report_timer_status(self, ierr, status, message)
         return
      end if

#ifdef FTIMER_USE_MPI
      if ((.not. is_inside_parallel_region()) .and. &
          (.not. should_emit_mpi_openmp_summary_diagnostic(self))) return
#endif
      call report_timer_status(self, ierr, status, message)
   end subroutine report_mpi_openmp_summary_status

   logical function should_emit_mpi_openmp_summary_diagnostic(self) result(should_emit)
      class(ftimer_openmp_t), intent(in) :: self
#ifdef FTIMER_USE_MPI
      integer :: mpierr
      integer :: rank
#endif

      should_emit = .true.
#ifdef FTIMER_USE_MPI
      if (.not. self%initialized) return
      if (self%mpi_comm%MPI_VAL == MPI_COMM_NULL%MPI_VAL) return
      call MPI_Comm_rank(self%mpi_comm, rank, mpierr)
      if (mpierr == MPI_SUCCESS) should_emit = (rank == 0)
#endif
   end function should_emit_mpi_openmp_summary_diagnostic

   integer function prepare_openmp_summary(self, summary, diagnostics_are_explicit) result(status)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_summary_t), intent(out) :: summary
      logical, intent(in) :: diagnostics_are_explicit
      logical :: did_drain

      if (.not. self%initialized) then
         call reset_openmp_summary(summary)
         status = FTIMER_ERR_NOT_INIT
         return
      end if

      if (is_inside_parallel_region()) then
         call reset_openmp_summary(summary)
         status = FTIMER_ERR_ACTIVE
         return
      end if

      if (self%region_open .or. has_active_lanes(self)) then
         call reset_openmp_summary(summary)
         status = FTIMER_ERR_ACTIVE
         return
      end if

      if (diagnostics_are_explicit) then
         if (drain_worker_diagnostics(self, status)) then
            call reset_openmp_summary(summary)
            return
         end if
      else
         did_drain = drain_worker_diagnostics(self)
      end if

      call build_openmp_summary(self, summary)
      status = FTIMER_SUCCESS
   end function prepare_openmp_summary

   subroutine build_openmp_summary(self, summary)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_summary_t), intent(out) :: summary
      type(ftimer_openmp_entry_accumulator_t), allocatable :: accumulators(:)
      integer, allocatable :: order(:)
      logical, allocatable :: observed_lanes(:)
      character(len=:), allocatable :: parent_path
      character(len=:), allocatable :: path
      integer :: acc_idx
      integer :: catalog_idx
      integer :: ctx
      integer :: entry_count
      integer :: lane_idx
      integer :: lane_capacity
      integer :: pos
      real(wp) :: end_time

      call reset_openmp_summary(summary)
      end_time = openmp_clock(self)
      summary%start_date = self%init_date
      summary%end_date = ftimer_date_string()
      summary%summary_window_time = end_time - self%init_wtime
      summary%timed_region_envelope_time = self%timed_region_envelope_time
      summary%configured_lane_capacity = self%config%max_lanes

      lane_capacity = 0
      if (allocated(self%lanes)) lane_capacity = size(self%lanes)
      if (lane_capacity > 0) then
         allocate (observed_lanes(lane_capacity))
         observed_lanes = .false.
      else
         allocate (observed_lanes(0))
      end if

      entry_count = 0
      do lane_idx = 1, lane_capacity
         if (.not. allocated(self%lanes(lane_idx)%segments)) cycle
         do catalog_idx = 1, min(self%num_timers, size(self%lanes(lane_idx)%segments))
            if (.not. allocated(self%lanes(lane_idx)%segments(catalog_idx)%time)) cycle
            do ctx = 1, self%lanes(lane_idx)%segments(catalog_idx)%contexts%count
               if (.not. context_participates(self%lanes(lane_idx)%segments(catalog_idx), ctx)) cycle

               parent_path = descriptor_path_for_stack(self, &
                                                       self%lanes(lane_idx)%segments(catalog_idx)%contexts%stacks(ctx))
               path = descriptor_path_with_timer(self, parent_path, self%catalog(catalog_idx)%id)
               call find_or_add_openmp_accumulator(accumulators, entry_count, path, parent_path, &
                                                   self%catalog(catalog_idx)%name, &
                                                   self%lanes(lane_idx)%segments(catalog_idx)%contexts%stacks(ctx)%depth, &
                                                   lane_capacity, acc_idx)
               call add_openmp_accumulator_sample(self, accumulators(acc_idx), self%lanes(lane_idx)%lane_id, &
                                                  self%lanes(lane_idx)%segments(catalog_idx)%context_epoch(ctx), &
                                                  self%lanes(lane_idx)%segments(catalog_idx)% &
                                                  context_max_worker_lane_count(ctx), &
                                                  self%lanes(lane_idx)%segments(catalog_idx)%time(ctx), &
                                                  lane_context_self_time(self, lane_idx, catalog_idx, ctx), &
                                                  self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx))
               observed_lanes(lane_idx) = .true.
            end do
         end do
      end do

      summary%observed_participating_lane_count = count(observed_lanes)
      if (entry_count <= 0) then
         allocate (summary%entries(0))
         return
      end if

      allocate (order(entry_count))
      do pos = 1, entry_count
         order(pos) = pos
      end do
      call sort_openmp_accumulator_order(order, accumulators)

      summary%num_entries = entry_count
      allocate (summary%entries(entry_count))
      do pos = 1, entry_count
         call populate_openmp_summary_entry(summary%entries(pos), accumulators(order(pos)))
         summary%entries(pos)%node_id = pos
      end do

      do pos = 1, entry_count
         summary%entries(pos)%parent_id = ordered_parent_id(accumulators(order(pos))%parent_path, accumulators, order)
         if (summary%entries(pos)%depth == 0) then
            summary%sum_lane_root_inclusive_time = summary%sum_lane_root_inclusive_time + &
                                                   summary%entries(pos)%sum_lane_inclusive_time
         end if
         summary%sum_lane_self_time = summary%sum_lane_self_time + summary%entries(pos)%sum_lane_self_time
      end do
   end subroutine build_openmp_summary

   subroutine reset_openmp_summary(summary)
      type(ftimer_openmp_summary_t), intent(out) :: summary

      if (allocated(summary%entries)) deallocate (summary%entries)
      summary%start_date = ''
      summary%end_date = ''
      summary%summary_window_time = 0.0_wp
      summary%timed_region_envelope_time = 0.0_wp
      summary%sum_lane_root_inclusive_time = 0.0_wp
      summary%sum_lane_self_time = 0.0_wp
      summary%configured_lane_capacity = 0
      summary%observed_participating_lane_count = 0
      summary%num_entries = 0
   end subroutine reset_openmp_summary

   logical function context_participates(segment, ctx) result(participates)
      type(ftimer_segment_t), intent(in) :: segment
      integer, intent(in) :: ctx

      participates = .false.
      if ((.not. allocated(segment%time)) .or. (.not. allocated(segment%call_count))) return
      if ((ctx < 1) .or. (ctx > size(segment%time)) .or. (ctx > size(segment%call_count))) return

      participates = (segment%call_count(ctx) > 0_int64) .or. (segment%time(ctx) /= 0.0_wp)
   end function context_participates

   real(wp) function lane_context_self_time(self, lane_idx, catalog_idx, ctx) result(self_time)
      class(ftimer_openmp_t), intent(in) :: self
      integer, intent(in) :: lane_idx
      integer, intent(in) :: catalog_idx
      integer, intent(in) :: ctx
      type(ftimer_call_stack_t) :: parent_stack
      integer :: child_catalog_idx
      integer :: child_ctx
      real(wp) :: child_sum
      real(wp) :: inclusive_time

      inclusive_time = self%lanes(lane_idx)%segments(catalog_idx)%time(ctx)
      parent_stack = self%lanes(lane_idx)%segments(catalog_idx)%contexts%stacks(ctx)
      child_sum = 0.0_wp

      if (allocated(self%lanes(lane_idx)%segments)) then
         do child_catalog_idx = 1, min(self%num_timers, size(self%lanes(lane_idx)%segments))
            if (.not. allocated(self%lanes(lane_idx)%segments(child_catalog_idx)%time)) cycle
            do child_ctx = 1, self%lanes(lane_idx)%segments(child_catalog_idx)%contexts%count
               if (.not. context_participates(self%lanes(lane_idx)%segments(child_catalog_idx), child_ctx)) cycle
               if (is_direct_child_context(self%lanes(lane_idx)%segments(child_catalog_idx)%contexts%stacks(child_ctx), &
                                           parent_stack, self%catalog(catalog_idx)%id)) then
                  child_sum = child_sum + self%lanes(lane_idx)%segments(child_catalog_idx)%time(child_ctx)
               end if
            end do
         end do
      end if

      self_time = inclusive_time - child_sum
      if (self_time < 0.0_wp) self_time = 0.0_wp
      if (self_time > inclusive_time) self_time = inclusive_time
   end function lane_context_self_time

   logical function is_direct_child_context(child_stack, parent_stack, timer_id) result(is_child)
      type(ftimer_call_stack_t), intent(in) :: child_stack
      type(ftimer_call_stack_t), intent(in) :: parent_stack
      integer, intent(in) :: timer_id

      is_child = .false.
      if (child_stack%depth /= parent_stack%depth + 1) return
      if (parent_stack%depth > 0) then
         if (.not. all(child_stack%ids(1:parent_stack%depth) == parent_stack%ids(1:parent_stack%depth))) return
      end if
      is_child = child_stack%ids(parent_stack%depth + 1) == timer_id
   end function is_direct_child_context

   subroutine find_or_add_openmp_accumulator(accumulators, entry_count, path, parent_path, name, depth, lane_capacity, idx)
      type(ftimer_openmp_entry_accumulator_t), allocatable, intent(inout) :: accumulators(:)
      integer, intent(inout) :: entry_count
      character(len=*), intent(in) :: path
      character(len=*), intent(in) :: parent_path
      character(len=*), intent(in) :: name
      integer, intent(in) :: depth
      integer, intent(in) :: lane_capacity
      integer, intent(out) :: idx
      type(ftimer_openmp_entry_accumulator_t), allocatable :: old_accumulators(:)
      integer :: new_size

      if (allocated(accumulators)) then
         do idx = 1, entry_count
            if (accumulators(idx)%path == path) return
         end do
      end if

      if (allocated(accumulators)) then
         if (entry_count >= size(accumulators)) then
            call move_alloc(accumulators, old_accumulators)
            new_size = max(entry_count + 1, 2*size(old_accumulators))
            allocate (accumulators(new_size))
            if (entry_count > 0) accumulators(1:entry_count) = old_accumulators(1:entry_count)
         end if
      else
         allocate (accumulators(max(1, FTIMER_OPENMP_CATALOG_INITIAL_CAPACITY)))
      end if

      entry_count = entry_count + 1
      idx = entry_count
      accumulators(idx)%path = path
      accumulators(idx)%parent_path = parent_path
      accumulators(idx)%name = name
      accumulators(idx)%depth = depth
      allocate (accumulators(idx)%lane_seen(lane_capacity))
      allocate (accumulators(idx)%lane_inclusive(lane_capacity))
      allocate (accumulators(idx)%lane_self(lane_capacity))
      allocate (accumulators(idx)%lane_calls(lane_capacity))
      accumulators(idx)%lane_seen = .false.
      accumulators(idx)%lane_inclusive = 0.0_wp
      accumulators(idx)%lane_self = 0.0_wp
      accumulators(idx)%lane_calls = 0_int64
   end subroutine find_or_add_openmp_accumulator

   subroutine add_openmp_accumulator_sample(self, accumulator, lane_id, epoch, context_worker_lane_count, &
                                            inclusive_time, self_time, call_count)
      class(ftimer_openmp_t), intent(in) :: self
      type(ftimer_openmp_entry_accumulator_t), intent(inout) :: accumulator
      integer, intent(in) :: lane_id
      integer, intent(in) :: epoch
      integer, intent(in) :: context_worker_lane_count
      real(wp), intent(in) :: inclusive_time
      real(wp), intent(in) :: self_time
      integer(int64), intent(in) :: call_count
      integer :: lane_idx
      integer :: worker_lane_count

      lane_idx = lane_id + 1
      if ((lane_idx >= 1) .and. (lane_idx <= size(accumulator%lane_seen))) then
         accumulator%lane_seen(lane_idx) = .true.
         accumulator%lane_inclusive(lane_idx) = accumulator%lane_inclusive(lane_idx) + inclusive_time
         accumulator%lane_self(lane_idx) = accumulator%lane_self(lane_idx) + self_time
         accumulator%lane_calls(lane_idx) = accumulator%lane_calls(lane_idx) + call_count
      end if

      if (lane_id == 0) then
         accumulator%eligible_serial_lane = .true.
      else
         worker_lane_count = context_worker_lane_count
         if (worker_lane_count <= 0) worker_lane_count = epoch_worker_lane_count(self, epoch)
         if (worker_lane_count <= 0) then
            worker_lane_count = lane_id
            accumulator%missing_lane_count_known = .false.
         end if
         if (epoch == FTIMER_OPENMP_CONTEXT_EPOCH_UNKNOWN) accumulator%missing_lane_count_known = .false.
         if ((accumulator%max_worker_lane_id > 0) .and. (accumulator%max_worker_lane_id /= worker_lane_count)) then
            accumulator%missing_lane_count_known = .false.
         end if
         accumulator%max_worker_lane_id = max(accumulator%max_worker_lane_id, worker_lane_count)
      end if
   end subroutine add_openmp_accumulator_sample

   integer function epoch_worker_lane_count(self, epoch) result(worker_lane_count)
      class(ftimer_openmp_t), intent(in) :: self
      integer, intent(in) :: epoch

      worker_lane_count = 0
      if (epoch <= 0) return
      if (.not. allocated(self%epoch_team_size)) return
      if (epoch > size(self%epoch_team_size)) return
      worker_lane_count = self%epoch_team_size(epoch)
   end function epoch_worker_lane_count

   subroutine populate_openmp_summary_entry(entry, accumulator)
      type(ftimer_openmp_summary_entry_t), intent(out) :: entry
      type(ftimer_openmp_entry_accumulator_t), intent(in) :: accumulator
      integer :: i
      integer :: participating_count
      real(wp) :: sum_calls

      entry%name = accumulator%name
      entry%depth = accumulator%depth
      entry%eligible_lane_count = accumulator%max_worker_lane_id
      if (accumulator%eligible_serial_lane) entry%eligible_lane_count = entry%eligible_lane_count + 1
      participating_count = count(accumulator%lane_seen)
      entry%participating_lane_count = participating_count
      entry%missing_lane_count = max(0, entry%eligible_lane_count - participating_count)
      entry%missing_lane_count_known = accumulator%missing_lane_count_known

      if (participating_count <= 0) return

      entry%min_lane_inclusive_time = huge(entry%min_lane_inclusive_time)
      entry%min_lane_self_time = huge(entry%min_lane_self_time)
      entry%min_lane_call_count = huge(entry%min_lane_call_count)
      sum_calls = 0.0_wp
      do i = 1, size(accumulator%lane_seen)
         if (.not. accumulator%lane_seen(i)) cycle
         entry%sum_lane_inclusive_time = entry%sum_lane_inclusive_time + accumulator%lane_inclusive(i)
         entry%sum_lane_self_time = entry%sum_lane_self_time + accumulator%lane_self(i)
         entry%min_lane_inclusive_time = min(entry%min_lane_inclusive_time, accumulator%lane_inclusive(i))
         entry%max_lane_inclusive_time = max(entry%max_lane_inclusive_time, accumulator%lane_inclusive(i))
         entry%min_lane_self_time = min(entry%min_lane_self_time, accumulator%lane_self(i))
         entry%max_lane_self_time = max(entry%max_lane_self_time, accumulator%lane_self(i))
         entry%min_lane_call_count = min(entry%min_lane_call_count, accumulator%lane_calls(i))
         entry%max_lane_call_count = max(entry%max_lane_call_count, accumulator%lane_calls(i))
         sum_calls = sum_calls + real(accumulator%lane_calls(i), wp)
      end do

      entry%avg_lane_inclusive_time = entry%sum_lane_inclusive_time/real(participating_count, wp)
      entry%avg_lane_self_time = entry%sum_lane_self_time/real(participating_count, wp)
      entry%avg_lane_call_count = sum_calls/real(participating_count, wp)
      entry%lane_inclusive_imbalance = compute_openmp_imbalance(entry%max_lane_inclusive_time, &
                                                                entry%avg_lane_inclusive_time)
      entry%lane_self_imbalance = compute_openmp_imbalance(entry%max_lane_self_time, entry%avg_lane_self_time)
   end subroutine populate_openmp_summary_entry

   real(wp) function compute_openmp_imbalance(max_value, avg_value) result(imbalance)
      real(wp), intent(in) :: max_value
      real(wp), intent(in) :: avg_value

      if (avg_value > 0.0_wp) then
         imbalance = max_value/avg_value
      else
         imbalance = 1.0_wp
      end if
   end function compute_openmp_imbalance

   subroutine sort_openmp_accumulator_order(order, accumulators)
      integer, intent(inout) :: order(:)
      type(ftimer_openmp_entry_accumulator_t), intent(in) :: accumulators(:)
      integer :: i
      integer :: j
      integer :: tmp

      do i = 2, size(order)
         tmp = order(i)
         j = i - 1
         do while (j >= 1)
            if (accumulators(order(j))%path <= accumulators(tmp)%path) exit
            order(j + 1) = order(j)
            j = j - 1
         end do
         order(j + 1) = tmp
      end do
   end subroutine sort_openmp_accumulator_order

   integer function ordered_parent_id(parent_path, accumulators, order) result(parent_id)
      character(len=*), intent(in) :: parent_path
      type(ftimer_openmp_entry_accumulator_t), intent(in) :: accumulators(:)
      integer, intent(in) :: order(:)
      integer :: i

      parent_id = 0
      if (len(parent_path) <= 0) return
      do i = 1, size(order)
         if (accumulators(order(i))%path == parent_path) then
            parent_id = i
            return
         end if
      end do
   end function ordered_parent_id

   function descriptor_path_for_stack(self, stack) result(path)
      class(ftimer_openmp_t), intent(in) :: self
      type(ftimer_call_stack_t), intent(in) :: stack
      character(len=:), allocatable :: path
      integer :: i

      path = ''
      do i = 1, stack%depth
         path = descriptor_path_with_timer(self, path, stack%ids(i))
      end do
   end function descriptor_path_for_stack

   function descriptor_path_with_timer(self, parent_path, timer_id) result(path)
      class(ftimer_openmp_t), intent(in) :: self
      character(len=*), intent(in) :: parent_path
      integer, intent(in) :: timer_id
      character(len=:), allocatable :: component
      character(len=:), allocatable :: name
      character(len=:), allocatable :: path
      character(len=32) :: len_text

      name = timer_name_for_id(self, timer_id)
      write (len_text, '(i0)') len(name)
      component = trim(len_text)//':'//name
      if (len(parent_path) > 0) then
         path = parent_path//'/'//component
      else
         path = component
      end if
   end function descriptor_path_with_timer

   function timer_name_for_id(self, timer_id) result(name)
      class(ftimer_openmp_t), intent(in) :: self
      integer, intent(in) :: timer_id
      character(len=:), allocatable :: name
      integer :: idx

      idx = find_timer_id_index(self, timer_id)
      if (idx > 0) then
         name = self%catalog(idx)%name
      else
         name = '<unknown>'
      end if
   end function timer_name_for_id

   subroutine format_openmp_summary(summary, text, metadata)
      type(ftimer_openmp_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      type(openmp_report_buffer_t) :: buffer
      character(len=:), allocatable :: display
      character(len=:), allocatable :: line
      integer :: i
      integer :: key_width
      integer :: line_width
      integer :: name_width

      call init_openmp_report_buffer(buffer, default_report_buffer_capacity)
      call append_openmp_line(buffer, 'OpenMP summary')

      key_width = openmp_metadata_key_width(metadata)
      key_width = max(key_width, len('Summary window time (s)'))
      key_width = max(key_width, len('Timed region envelope time (s)'))
      key_width = max(key_width, len('Configured lane capacity'))
      key_width = max(key_width, len('Observed participating lanes'))
      key_width = max(key_width, len('Summed lane root work (s)'))
      key_width = max(key_width, len('Summed lane self work (s)'))

      call append_openmp_real_metric(buffer, 'Summary window time (s)', key_width, summary%summary_window_time)
      call append_openmp_real_metric(buffer, 'Timed region envelope time (s)', key_width, &
                                     summary%timed_region_envelope_time)
      call append_openmp_integer_metric(buffer, 'Configured lane capacity', key_width, &
                                        summary%configured_lane_capacity)
      call append_openmp_integer_metric(buffer, 'Observed participating lanes', key_width, &
                                        summary%observed_participating_lane_count)
      call append_openmp_real_metric(buffer, 'Summed lane root work (s)', key_width, &
                                     summary%sum_lane_root_inclusive_time)
      call append_openmp_real_metric(buffer, 'Summed lane self work (s)', key_width, summary%sum_lane_self_time)

      if (present(metadata)) then
         do i = 1, size(metadata)
            if (openmp_metadata_key_len(metadata(i)) <= 0) cycle
            call append_openmp_text_metric(buffer, openmp_metadata_key_text(metadata(i)), key_width, &
                                           openmp_metadata_value_text(metadata(i)))
         end do
      end if

      call append_openmp_line(buffer, '')
      call append_openmp_line(buffer, &
                              'Report note: lane min/avg/max fields are over participating lanes only; '// &
                              'missing lanes are not zero-filled.')
      call append_openmp_line(buffer, &
                              'Report note: timed-region envelope time is wall-clock time, not summed lane work.')
      call append_openmp_line(buffer, '')

      name_width = openmp_summary_name_width(summary)
      line_width = name_width + 220
      allocate (character(len=line_width) :: line)
      write (line, '(a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a)') &
         padded_openmp_text('Timer name', name_width), 'Part', 'Missing', 'Sum Incl (s)', 'Sum Self (s)', &
         'Min Lane Incl (s)', 'Avg Lane Incl (s)', 'Max Lane Incl (s)', 'Avg Lane Self (s)', &
         'Min Calls', 'Avg Calls', 'Max Calls'
      call append_openmp_line(buffer, trim(line))
      call append_openmp_line(buffer, repeat('-', len_trim(line)))

      do i = 1, summary%num_entries
         display = repeat(' ', 2*summary%entries(i)%depth)//openmp_entry_name(summary%entries(i))
         write (line, '(a,2x,i4,2x,i7,2x,f12.6,2x,f12.6,2x,f17.6,2x,f17.6,2x,f17.6,2x,f17.6,2x,i9,2x,f9.3,2x,i9)') &
            padded_openmp_text(display, name_width), summary%entries(i)%participating_lane_count, &
            summary%entries(i)%missing_lane_count, summary%entries(i)%sum_lane_inclusive_time, &
            summary%entries(i)%sum_lane_self_time, summary%entries(i)%min_lane_inclusive_time, &
            summary%entries(i)%avg_lane_inclusive_time, summary%entries(i)%max_lane_inclusive_time, &
            summary%entries(i)%avg_lane_self_time, summary%entries(i)%min_lane_call_count, &
            summary%entries(i)%avg_lane_call_count, summary%entries(i)%max_lane_call_count
         call append_openmp_line(buffer, trim(line))
      end do

      call finish_openmp_report_buffer(buffer, text)
   end subroutine format_openmp_summary

   subroutine append_openmp_real_metric(buffer, label, key_width, value)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: label
      integer, intent(in) :: key_width
      real(wp), intent(in) :: value
      character(len=64) :: value_text

      write (value_text, '(f0.6)') value
      call append_openmp_text_metric(buffer, label, key_width, trim(value_text))
   end subroutine append_openmp_real_metric

   subroutine append_openmp_integer_metric(buffer, label, key_width, value)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: label
      integer, intent(in) :: key_width
      integer, intent(in) :: value
      character(len=32) :: value_text

      write (value_text, '(i0)') value
      call append_openmp_text_metric(buffer, label, key_width, trim(value_text))
   end subroutine append_openmp_integer_metric

   subroutine append_openmp_text_metric(buffer, label, key_width, value)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: label
      integer, intent(in) :: key_width
      character(len=*), intent(in) :: value

      call append_openmp_line(buffer, padded_openmp_text(label, key_width)//' : '//value)
   end subroutine append_openmp_text_metric

   integer function openmp_summary_name_width(summary) result(width)
      type(ftimer_openmp_summary_t), intent(in) :: summary
      integer :: i

      width = len('Timer name')
      do i = 1, summary%num_entries
         width = max(width, 2*summary%entries(i)%depth + len(openmp_entry_name(summary%entries(i))))
      end do
   end function openmp_summary_name_width

   function padded_openmp_text(value, width) result(text)
      character(len=*), intent(in) :: value
      integer, intent(in) :: width
      character(len=:), allocatable :: text
      integer :: copy_len

      allocate (character(len=max(width, len_trim(value))) :: text)
      text = repeat(' ', len(text))
      copy_len = min(len(text), len_trim(value))
      if (copy_len > 0) text(1:copy_len) = value(1:copy_len)
   end function padded_openmp_text

   subroutine format_openmp_summary_csv(summary, text, metadata, include_header)
      type(ftimer_openmp_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      logical, intent(in), optional :: include_header
      type(openmp_report_buffer_t) :: buffer
      integer :: i
      logical :: emit_header

      call init_openmp_report_buffer(buffer, default_report_buffer_capacity)
      emit_header = .true.
      if (present(include_header)) emit_header = include_header

      if (emit_header) call append_openmp_line(buffer, openmp_csv_header_line())
      call append_openmp_summary_csv_record(buffer, summary)
      if (present(metadata)) then
         do i = 1, size(metadata)
            if (openmp_metadata_key_len(metadata(i)) <= 0) cycle
            call append_openmp_metadata_csv_record(buffer, metadata(i))
         end do
      end if
      do i = 1, summary%num_entries
         call append_openmp_entry_csv_record(buffer, summary%entries(i))
      end do

      call finish_openmp_report_buffer(buffer, text)
   end subroutine format_openmp_summary_csv

   subroutine append_openmp_summary_csv_record(buffer, summary)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_openmp_summary_t), intent(in) :: summary
      type(openmp_report_buffer_t) :: row

      call begin_openmp_csv_row(row, 'summary')
      call append_empty_openmp_csv_fields(row, 2)
      call append_openmp_csv_field(row, summary%start_date)
      call append_openmp_csv_field(row, summary%end_date)
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%configured_lane_capacity))
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%observed_participating_lane_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%num_entries))
      call append_empty_openmp_csv_fields(row, 21)
      call append_openmp_row(buffer, row)
   end subroutine append_openmp_summary_csv_record

   subroutine append_openmp_metadata_csv_record(buffer, item)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_metadata_t), intent(in) :: item
      type(openmp_report_buffer_t) :: row

      call begin_openmp_csv_row(row, 'metadata')
      call append_openmp_csv_field(row, openmp_metadata_key_text(item))
      call append_openmp_csv_field(row, openmp_metadata_value_text(item))
      call append_empty_openmp_csv_fields(row, 30)
      call append_openmp_row(buffer, row)
   end subroutine append_openmp_metadata_csv_record

   subroutine append_openmp_entry_csv_record(buffer, entry)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_openmp_summary_entry_t), intent(in) :: entry
      type(openmp_report_buffer_t) :: row

      call begin_openmp_csv_row(row, 'entry')
      call append_empty_openmp_csv_fields(row, 11)
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%node_id))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%parent_id))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%depth))
      call append_openmp_csv_field(row, openmp_entry_name(entry))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%eligible_lane_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%participating_lane_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%missing_lane_count))
      call append_openmp_csv_field(row, openmp_logical_csv_text(entry%missing_lane_count_known))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%sum_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%lane_inclusive_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%lane_self_imbalance))
      call append_openmp_csv_field(row, openmp_int64_csv_text(entry%min_lane_call_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_lane_call_count))
      call append_openmp_csv_field(row, openmp_int64_csv_text(entry%max_lane_call_count))
      call append_openmp_row(buffer, row)
   end subroutine append_openmp_entry_csv_record

   subroutine begin_openmp_csv_row(row, record_type)
      type(openmp_report_buffer_t), intent(out) :: row
      character(len=*), intent(in) :: record_type

      call init_openmp_report_buffer(row, 512)
      call append_openmp_csv_field(row, FTIMER_OPENMP_CSV_FORMAT_VERSION)
      call append_openmp_csv_field(row, 'openmp')
      call append_openmp_csv_field(row, record_type)
   end subroutine begin_openmp_csv_row

   function openmp_csv_header_line() result(line)
      character(len=:), allocatable :: line
      type(openmp_report_buffer_t) :: row

      call init_openmp_report_buffer(row, 1024)
      call append_openmp_csv_field(row, 'format_version')
      call append_openmp_csv_field(row, 'summary_kind')
      call append_openmp_csv_field(row, 'record_type')
      call append_openmp_csv_field(row, 'key')
      call append_openmp_csv_field(row, 'value')
      call append_openmp_csv_field(row, 'start_date')
      call append_openmp_csv_field(row, 'end_date')
      call append_openmp_csv_field(row, 'summary_window_time')
      call append_openmp_csv_field(row, 'timed_region_envelope_time')
      call append_openmp_csv_field(row, 'sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'sum_lane_self_time')
      call append_openmp_csv_field(row, 'configured_lane_capacity')
      call append_openmp_csv_field(row, 'observed_participating_lane_count')
      call append_openmp_csv_field(row, 'num_entries')
      call append_openmp_csv_field(row, 'node_id')
      call append_openmp_csv_field(row, 'parent_id')
      call append_openmp_csv_field(row, 'depth')
      call append_openmp_csv_field(row, 'name')
      call append_openmp_csv_field(row, 'eligible_lane_count')
      call append_openmp_csv_field(row, 'participating_lane_count')
      call append_openmp_csv_field(row, 'missing_lane_count')
      call append_openmp_csv_field(row, 'missing_lane_count_known')
      call append_openmp_csv_field(row, 'sum_lane_inclusive_time')
      call append_openmp_csv_field(row, 'sum_lane_self_time')
      call append_openmp_csv_field(row, 'min_lane_inclusive_time')
      call append_openmp_csv_field(row, 'avg_lane_inclusive_time')
      call append_openmp_csv_field(row, 'max_lane_inclusive_time')
      call append_openmp_csv_field(row, 'lane_inclusive_imbalance')
      call append_openmp_csv_field(row, 'min_lane_self_time')
      call append_openmp_csv_field(row, 'avg_lane_self_time')
      call append_openmp_csv_field(row, 'max_lane_self_time')
      call append_openmp_csv_field(row, 'lane_self_imbalance')
      call append_openmp_csv_field(row, 'min_lane_call_count')
      call append_openmp_csv_field(row, 'avg_lane_call_count')
      call append_openmp_csv_field(row, 'max_lane_call_count')
      call finish_openmp_report_buffer(row, line)
   end function openmp_csv_header_line

   subroutine get_openmp_csv_header_mode(filename, append_mode, include_header, status, iomsg)
      character(len=*), intent(in) :: filename
      logical, intent(in) :: append_mode
      logical, intent(out) :: include_header
      integer, intent(out) :: status
      character(len=*), intent(out) :: iomsg
      character(len=1) :: ch
      character(len=:), allocatable :: expected_header
      character(len=:), allocatable :: header_line
      character(len=:), allocatable :: record_text
      character(len=1) :: last_char
      integer :: expected_field_count
      integer :: io
      integer :: record_field_count
      integer :: record_prefix_limit
      integer :: unit
      logical :: exists
      logical :: after_quoted_field
      logical :: field_has_content
      logical :: in_quotes
      logical :: pending_record_cr
      logical :: pending_quote
      logical :: reading_header
      logical :: saw_any_char

      include_header = .true.
      status = FTIMER_SUCCESS
      iomsg = ''
      if (.not. append_mode) return

      inquire (file=filename, exist=exists)
      if (.not. exists) return

      expected_header = openmp_csv_header_line()
      expected_field_count = openmp_csv_field_count(expected_header)
      header_line = ''
      record_text = ''
      record_prefix_limit = 64
      record_field_count = 1
      last_char = ''
      reading_header = .true.
      after_quoted_field = .false.
      field_has_content = .false.
      in_quotes = .false.
      pending_record_cr = .false.
      pending_quote = .false.
      saw_any_char = .false.

      open (newunit=unit, file=filename, status='old', access='stream', form='unformatted', &
            action='read', iostat=io, iomsg=iomsg)
      if (io /= 0) then
         status = FTIMER_ERR_IO
         return
      end if

      do
         read (unit, iostat=io, iomsg=iomsg) ch
         if (io == iostat_end) exit
         if (io /= 0) then
            close (unit)
            status = FTIMER_ERR_IO
            return
         end if

         last_char = ch
         saw_any_char = .true.

         if (reading_header) then
            if (ch == new_line('a')) then
               reading_header = .false.
               call strip_openmp_trailing_carriage_return(header_line)
               if ((len(header_line) /= len(expected_header)) .or. (header_line /= expected_header)) then
                  close (unit)
                  status = FTIMER_ERR_IO
                  iomsg = 'existing OpenMP summary CSV header does not match format version 1'
                  return
               end if
            else
               header_line = header_line//ch
               if (len(header_line) > len(expected_header) + 1) then
                  close (unit)
                  status = FTIMER_ERR_IO
                  iomsg = 'existing OpenMP summary CSV header does not match format version 1'
                  return
               end if
            end if
            cycle
         end if

         if (pending_record_cr) then
            if (ch /= new_line('a')) then
               close (unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing OpenMP summary CSV records contain a bare carriage return'
               return
            end if
            pending_record_cr = .false.
         end if

         if (pending_quote) then
            if (ch == '"') then
               pending_quote = .false.
               call append_limited_openmp_csv_record_prefix(record_text, ch, record_prefix_limit)
               cycle
            end if
            in_quotes = .false.
            pending_quote = .false.
            after_quoted_field = .true.
         end if

         if ((ch == achar(13)) .and. (.not. in_quotes)) then
            pending_record_cr = .true.
            cycle
         end if

         if (after_quoted_field) then
            if ((ch /= ',') .and. (ch /= new_line('a'))) then
               close (unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing OpenMP summary CSV records contain malformed quoted fields'
               return
            end if
         end if

         if ((ch == new_line('a')) .and. (.not. in_quotes)) then
            call strip_openmp_trailing_carriage_return(record_text)
            if ((record_field_count /= expected_field_count) .or. &
                (.not. openmp_csv_record_has_valid_prefix(record_text))) then
               close (unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing OpenMP summary CSV records do not match format version 1'
               return
            end if
            record_text = ''
            record_field_count = 1
            after_quoted_field = .false.
            field_has_content = .false.
            cycle
         end if

         call append_limited_openmp_csv_record_prefix(record_text, ch, record_prefix_limit)

         if ((ch == ',') .and. (.not. in_quotes)) then
            record_field_count = record_field_count + 1
            if (after_quoted_field) after_quoted_field = .false.
            field_has_content = .false.
            cycle
         end if

         if (ch == '"') then
            if (in_quotes) then
               pending_quote = .true.
            else if (field_has_content) then
               close (unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing OpenMP summary CSV records contain malformed quoted fields'
               return
            else
               in_quotes = .true.
               after_quoted_field = .false.
            end if
         else if (.not. in_quotes) then
            field_has_content = .true.
         end if
      end do
      close (unit)

      if (.not. saw_any_char) return

      if (last_char /= new_line('a')) then
         status = FTIMER_ERR_IO
         iomsg = 'existing OpenMP summary CSV append target does not end with a newline'
         return
      end if

      if (in_quotes) then
         status = FTIMER_ERR_IO
         iomsg = 'existing OpenMP summary CSV records contain an unterminated quoted field'
         return
      end if

      if (pending_record_cr) then
         status = FTIMER_ERR_IO
         iomsg = 'existing OpenMP summary CSV records contain a bare carriage return'
         return
      end if

      include_header = .false.
   end subroutine get_openmp_csv_header_mode

   subroutine append_limited_openmp_csv_record_prefix(record_text, ch, prefix_limit)
      character(len=:), allocatable, intent(inout) :: record_text
      character(len=1), intent(in) :: ch
      integer, intent(in) :: prefix_limit

      if (len(record_text) >= prefix_limit) return
      record_text = record_text//ch
   end subroutine append_limited_openmp_csv_record_prefix

   subroutine strip_openmp_trailing_carriage_return(text)
      character(len=:), allocatable, intent(inout) :: text
      integer :: text_len

      text_len = len(text)
      if (text_len <= 0) return
      if (text(text_len:text_len) == achar(13)) text = text(:text_len - 1)
   end subroutine strip_openmp_trailing_carriage_return

   integer function openmp_csv_field_count(line) result(count)
      character(len=*), intent(in) :: line
      integer :: i
      logical :: in_quotes

      count = 1
      in_quotes = .false.
      do i = 1, len_trim(line)
         if (line(i:i) == '"') then
            in_quotes = .not. in_quotes
         elseif ((line(i:i) == ',') .and. (.not. in_quotes)) then
            count = count + 1
         end if
      end do
   end function openmp_csv_field_count

   logical function openmp_csv_record_has_valid_prefix(line) result(matches)
      character(len=*), intent(in) :: line

      matches = openmp_starts_with(line, '"'//FTIMER_OPENMP_CSV_FORMAT_VERSION//'","openmp","summary",') .or. &
                openmp_starts_with(line, '"'//FTIMER_OPENMP_CSV_FORMAT_VERSION//'","openmp","metadata",') .or. &
                openmp_starts_with(line, '"'//FTIMER_OPENMP_CSV_FORMAT_VERSION//'","openmp","entry",')
   end function openmp_csv_record_has_valid_prefix

   logical function openmp_starts_with(text, prefix) result(matches)
      character(len=*), intent(in) :: text
      character(len=*), intent(in) :: prefix

      matches = .false.
      if (len_trim(text) < len(prefix)) return
      matches = text(1:len(prefix)) == prefix
   end function openmp_starts_with

   subroutine append_empty_openmp_csv_fields(row, count)
      type(openmp_report_buffer_t), intent(inout) :: row
      integer, intent(in) :: count
      integer :: i

      do i = 1, count
         call append_openmp_csv_field(row, '')
      end do
   end subroutine append_empty_openmp_csv_fields

   subroutine append_openmp_csv_field(row, value)
      type(openmp_report_buffer_t), intent(inout) :: row
      character(len=*), intent(in) :: value
      integer :: i

      if (row%used > 0) call append_openmp_text(row, ',')
      call append_openmp_text(row, '"')
      do i = 1, len_trim(value)
         if (value(i:i) == '"') then
            call append_openmp_text(row, '""')
         else
            call append_openmp_text(row, value(i:i))
         end if
      end do
      call append_openmp_text(row, '"')
   end subroutine append_openmp_csv_field

   subroutine append_openmp_row(buffer, row)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(openmp_report_buffer_t), intent(in) :: row

      if (row%used > 0) call append_openmp_text(buffer, row%chars(1:row%used))
      call append_openmp_text(buffer, new_line('a'))
   end subroutine append_openmp_row

   function openmp_integer_csv_text(value) result(text)
      integer, intent(in) :: value
      character(len=:), allocatable :: text
      character(len=32) :: buffer

      write (buffer, '(i0)') value
      text = trim(buffer)
   end function openmp_integer_csv_text

   function openmp_int64_csv_text(value) result(text)
      integer(int64), intent(in) :: value
      character(len=:), allocatable :: text
      character(len=32) :: buffer

      write (buffer, '(i0)') value
      text = trim(buffer)
   end function openmp_int64_csv_text

   function openmp_real_csv_text(value) result(text)
      real(wp), intent(in) :: value
      character(len=:), allocatable :: text
      character(len=48) :: buffer

      write (buffer, '(es32.17e4)') value
      text = trim(adjustl(buffer))
   end function openmp_real_csv_text

   function openmp_logical_csv_text(value) result(text)
      logical, intent(in) :: value
      character(len=:), allocatable :: text

      if (value) then
         text = 'true'
      else
         text = 'false'
      end if
   end function openmp_logical_csv_text

   subroutine write_text_block(unit, text, io, iomsg)
      integer, intent(in) :: unit
      character(len=*), intent(in) :: text
      integer, intent(out) :: io
      character(len=*), intent(out) :: iomsg
      integer :: start
      integer :: line_end

      io = 0
      iomsg = ''
      start = 1
      do
         if (start > len(text)) exit
         line_end = index(text(start:), new_line('a'))
         if (line_end == 0) then
            write (unit, '(a)', iostat=io, iomsg=iomsg) text(start:)
            exit
         else
            line_end = start + line_end - 2
            if (line_end >= start) then
               write (unit, '(a)', iostat=io, iomsg=iomsg) text(start:line_end)
            else
               write (unit, '(a)', iostat=io, iomsg=iomsg) ''
            end if
            if (io /= 0) exit
            start = line_end + 2
         end if
      end do
   end subroutine write_text_block

   subroutine append_openmp_line(buffer, line)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: line

      call append_openmp_text(buffer, trim(line))
      call append_openmp_text(buffer, new_line('a'))
   end subroutine append_openmp_line

   subroutine init_openmp_report_buffer(buffer, initial_capacity)
      type(openmp_report_buffer_t), intent(out) :: buffer
      integer, intent(in) :: initial_capacity
      integer :: capacity

      capacity = max(1, initial_capacity)
      allocate (character(len=capacity) :: buffer%chars)
      buffer%used = 0
   end subroutine init_openmp_report_buffer

   subroutine append_openmp_text(buffer, fragment)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: fragment
      integer :: fragment_len
      integer :: next_used

      fragment_len = len(fragment)
      if (fragment_len <= 0) return

      next_used = buffer%used + fragment_len
      call ensure_openmp_report_capacity(buffer, next_used)
      buffer%chars(buffer%used + 1:next_used) = fragment
      buffer%used = next_used
   end subroutine append_openmp_text

   subroutine finish_openmp_report_buffer(buffer, text)
      type(openmp_report_buffer_t), intent(in) :: buffer
      character(len=:), allocatable, intent(out) :: text

      if (buffer%used > 0) then
         text = buffer%chars(1:buffer%used)
      else
         text = ''
      end if
   end subroutine finish_openmp_report_buffer

   subroutine ensure_openmp_report_capacity(buffer, required_capacity)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      integer, intent(in) :: required_capacity
      character(len=:), allocatable :: grown
      integer :: current_capacity
      integer :: new_capacity

      if (allocated(buffer%chars)) then
         current_capacity = len(buffer%chars)
      else
         current_capacity = 0
      end if
      if (current_capacity >= required_capacity) return

      new_capacity = max(default_report_buffer_capacity, current_capacity)
      if (new_capacity <= 0) new_capacity = default_report_buffer_capacity
      do while (new_capacity < required_capacity)
         if (new_capacity > huge(new_capacity)/2) then
            new_capacity = required_capacity
         else
            new_capacity = new_capacity*2
         end if
      end do

      allocate (character(len=new_capacity) :: grown)
      if (buffer%used > 0) grown(1:buffer%used) = buffer%chars(1:buffer%used)
      call move_alloc(grown, buffer%chars)
   end subroutine ensure_openmp_report_capacity

   integer function openmp_metadata_key_width(metadata) result(width)
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer :: i

      width = 0
      if (.not. present(metadata)) return
      do i = 1, size(metadata)
         width = max(width, len(openmp_metadata_key_text(metadata(i))))
      end do
   end function openmp_metadata_key_width

   integer function openmp_metadata_key_len(item) result(key_len)
      type(ftimer_metadata_t), intent(in) :: item

      if (allocated(item%key)) then
         key_len = len_trim(item%key)
      else
         key_len = 0
      end if
   end function openmp_metadata_key_len

   function openmp_metadata_key_text(item) result(text)
      type(ftimer_metadata_t), intent(in) :: item
      character(len=:), allocatable :: text

      if (allocated(item%key)) then
         text = trim(item%key)
      else
         text = ''
      end if
   end function openmp_metadata_key_text

   function openmp_metadata_value_text(item) result(text)
      type(ftimer_metadata_t), intent(in) :: item
      character(len=:), allocatable :: text

      if (allocated(item%value)) then
         text = trim(item%value)
      else
         text = ''
      end if
   end function openmp_metadata_value_text

   function openmp_entry_name(entry) result(name)
      type(ftimer_openmp_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name

      if (allocated(entry%name)) then
         name = entry%name
      else
         name = '<unnamed>'
      end if
   end function openmp_entry_name

   subroutine clear_state(self)
      class(ftimer_openmp_t), intent(inout) :: self

      self%initialized = .false.
      self%config = ftimer_openmp_config_t()
      if (allocated(self%catalog)) deallocate (self%catalog)
      if (allocated(self%id_to_catalog_idx)) deallocate (self%id_to_catalog_idx)
      self%id_index_base = 0
      if (allocated(self%lanes)) deallocate (self%lanes)
      self%num_timers = 0
      self%region_open = .false.
      self%current_epoch = 0
      self%current_region_token = 0_int64
      self%current_region_start_time = 0.0_wp
      self%timed_region_envelope_time = 0.0_wp
      self%next_epoch = 1
      self%init_wtime = 0.0_wp
      self%init_date = ''
      if (allocated(self%epoch_team_size)) deallocate (self%epoch_team_size)
      nullify (self%clock)
      call clear_worker_diagnostics(self)
#ifdef FTIMER_USE_MPI
      self%mpi_comm = MPI_COMM_WORLD
      self%mpi_comm_was_present = .false.
#endif
   end subroutine clear_state

   subroutine clear_region(region)
      type(ftimer_openmp_parallel_region_t), intent(inout) :: region

      region%epoch = 0
      region%object_token = 0_int64
      region%region_token = 0_int64
      region%active = .false.
   end subroutine clear_region

   logical function region_belongs_to_self(self, region) result(belongs)
      class(ftimer_openmp_t), intent(in) :: self
      type(ftimer_openmp_parallel_region_t), intent(in) :: region

      belongs = (.not. region%active) .or. &
                ((self%object_token /= 0_int64) .and. (region%object_token == self%object_token))
   end function region_belongs_to_self

   subroutine allocate_lanes(self)
      class(ftimer_openmp_t), intent(inout) :: self
      integer :: i

      if (allocated(self%lanes)) deallocate (self%lanes)
      allocate (self%lanes(self%config%max_lanes))
      do i = 1, size(self%lanes)
         self%lanes(i)%lane_id = i - 1
         self%lanes(i)%participated = .false.
      end do
   end subroutine allocate_lanes

   subroutine clear_all_lanes(self)
      class(ftimer_openmp_t), intent(inout) :: self

      call allocate_lanes(self)
   end subroutine clear_all_lanes

   logical function has_active_lanes(self) result(has_active)
      class(ftimer_openmp_t), intent(in) :: self
      integer :: i

      has_active = .false.
      if (.not. allocated(self%lanes)) return

      do i = 1, size(self%lanes)
         if (self%lanes(i)%call_stack%depth > 0) then
            has_active = .true.
            return
         end if
      end do
   end function has_active_lanes

   integer function resolve_timing_lane(self, lane_idx, epoch, worker_lane_count) result(status)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out) :: lane_idx
      integer, intent(out) :: epoch
      integer, intent(out) :: worker_lane_count
      integer :: lane_id

      lane_id = current_lane_id()
      lane_idx = lane_id + 1
      epoch = 0
      worker_lane_count = 0

      if ((.not. allocated(self%lanes)) .or. (lane_idx < 1) .or. (lane_idx > size(self%lanes))) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      if (lane_id == 0) then
         status = FTIMER_SUCCESS
         return
      end if

      if (current_parallel_level() /= 1) then
         status = FTIMER_ERR_ACTIVE
         return
      end if

      if (.not. self%region_open) then
         status = FTIMER_ERR_ACTIVE
         return
      end if

      epoch = self%current_epoch
      call note_current_epoch_team_size(self, epoch, worker_lane_count)
      status = FTIMER_SUCCESS
   end function resolve_timing_lane

   integer function current_lane_id() result(lane_id)
#ifdef FTIMER_USE_OPENMP
      if (omp_in_parallel()) then
         lane_id = 1 + omp_get_thread_num()
      else
         lane_id = 0
      end if
#else
      lane_id = 0
#endif
   end function current_lane_id

   integer function current_parallel_level() result(level)
#ifdef FTIMER_USE_OPENMP
      level = omp_get_level()
#else
      level = 0
#endif
   end function current_parallel_level

   integer function current_team_size() result(team_size)
#ifdef FTIMER_USE_OPENMP
      if (omp_in_parallel()) then
         team_size = omp_get_num_threads()
      else
         team_size = 0
      end if
#else
      team_size = 0
#endif
   end function current_team_size

   subroutine ensure_epoch_capacity(self, required_epoch)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: required_epoch
      integer, allocatable :: old_sizes(:)
      integer :: old_size
      integer :: new_size

      if (required_epoch <= 0) return

      if (allocated(self%epoch_team_size)) then
         if (size(self%epoch_team_size) >= required_epoch) return
         old_size = size(self%epoch_team_size)
         call move_alloc(self%epoch_team_size, old_sizes)
         new_size = max(required_epoch, 2*old_size)
         allocate (self%epoch_team_size(new_size))
         self%epoch_team_size = 0
         if (old_size > 0) self%epoch_team_size(1:old_size) = old_sizes
      else
         new_size = max(required_epoch, 8)
         allocate (self%epoch_team_size(new_size))
         self%epoch_team_size = 0
      end if
   end subroutine ensure_epoch_capacity

   subroutine note_current_epoch_team_size(self, epoch, worker_lane_count)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: epoch
      integer, intent(out) :: worker_lane_count
      integer :: team_size

      worker_lane_count = 0
      if (epoch <= 0) return
      team_size = current_team_size()
      if (team_size <= 0) return
      worker_lane_count = team_size

#ifdef FTIMER_USE_OPENMP
!$omp critical(ftimer_openmp_epoch_team_size)
#endif
      call ensure_epoch_capacity(self, epoch)
      self%epoch_team_size(epoch) = max(self%epoch_team_size(epoch), team_size)
#ifdef FTIMER_USE_OPENMP
!$omp end critical(ftimer_openmp_epoch_team_size)
#endif
   end subroutine note_current_epoch_team_size

   real(wp) function openmp_clock(self) result(t)
      class(ftimer_openmp_t), intent(in) :: self

      if (associated(self%clock)) then
         t = self%clock()
         return
      end if

      t = ftimer_default_clock()
   end function openmp_clock

   subroutine start_lane_timer(self, lane_idx, catalog_idx, timer_id, epoch, worker_lane_count, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: lane_idx
      integer, intent(in) :: catalog_idx
      integer, intent(in) :: timer_id
      integer, intent(in) :: epoch
      integer, intent(in) :: worker_lane_count
      integer, intent(out), optional :: ierr
      integer :: ctx

      call ensure_lane_segment_capacity(self%lanes(lane_idx), catalog_idx)
      call ensure_lane_timer_metadata(self%lanes(lane_idx), catalog_idx, self%catalog(catalog_idx)%name)

      ctx = self%lanes(lane_idx)%segments(catalog_idx)%contexts%add(self%lanes(lane_idx)%call_stack)
      call ensure_context_storage(self%lanes(lane_idx)%segments(catalog_idx), ctx)
      call note_context_epoch(self%lanes(lane_idx)%segments(catalog_idx), ctx, epoch, worker_lane_count)

      if (self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx) == &
          huge(self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx))) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp start_id call count overflow")
         return
      end if

      self%lanes(lane_idx)%participated = .true.
      self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx) = &
         self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx) + 1_int64
      self%lanes(lane_idx)%segments(catalog_idx)%is_running(ctx) = .true.
      self%lanes(lane_idx)%segments(catalog_idx)%start_time(ctx) = openmp_clock(self)
      call self%lanes(lane_idx)%call_stack%push(timer_id, int(epoch, int64))

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine start_lane_timer

   subroutine stop_lane_timer(self, lane_idx, catalog_idx, timer_id, epoch, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: lane_idx
      integer, intent(in) :: catalog_idx
      integer, intent(in) :: timer_id
      integer, intent(in) :: epoch
      integer, intent(out), optional :: ierr
      integer :: ctx
      integer :: popped_id
      integer(int64) :: popped_epoch
      real(wp) :: now

      if (self%lanes(lane_idx)%call_stack%depth <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_MISMATCH, "ftimer_openmp stop_id mismatch on empty lane stack")
         return
      end if

      if ((self%lanes(lane_idx)%call_stack%top() /= timer_id) .or. &
          (self%lanes(lane_idx)%call_stack%top_token() /= int(epoch, int64))) then
         call report_timer_status(self, ierr, FTIMER_ERR_MISMATCH, "ftimer_openmp stop_id lane stack mismatch")
         return
      end if

      now = openmp_clock(self)
      popped_id = self%lanes(lane_idx)%call_stack%pop(popped_epoch)
      if ((popped_id /= timer_id) .or. (popped_epoch /= int(epoch, int64))) then
         error stop "ftimer_openmp internal lane stack pop mismatch"
      end if

      ctx = self%lanes(lane_idx)%segments(catalog_idx)%contexts%find(self%lanes(lane_idx)%call_stack)
      if (ctx <= 0) error stop "ftimer_openmp internal stop_id missing lane context"

      self%lanes(lane_idx)%segments(catalog_idx)%time(ctx) = &
         self%lanes(lane_idx)%segments(catalog_idx)%time(ctx) + &
         (now - self%lanes(lane_idx)%segments(catalog_idx)%start_time(ctx))
      self%lanes(lane_idx)%segments(catalog_idx)%is_running(ctx) = .false.

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine stop_lane_timer

   subroutine ensure_lane_segment_capacity(lane, required_size)
      type(ftimer_openmp_lane_t), intent(inout) :: lane
      integer, intent(in) :: required_size
      type(ftimer_segment_t), allocatable :: old_segments(:)
      integer :: new_size

      if (required_size <= 0) return

      if (allocated(lane%segments)) then
         if (size(lane%segments) >= required_size) return
         call move_alloc(lane%segments, old_segments)
         new_size = max(required_size, 2*size(old_segments))
         allocate (lane%segments(new_size))
         if (size(old_segments) > 0) lane%segments(1:size(old_segments)) = old_segments
      else
         allocate (lane%segments(required_size))
      end if
   end subroutine ensure_lane_segment_capacity

   subroutine ensure_lane_timer_metadata(lane, catalog_idx, name)
      type(ftimer_openmp_lane_t), intent(inout) :: lane
      integer, intent(in) :: catalog_idx
      character(len=*), intent(in) :: name

      if (.not. allocated(lane%segments(catalog_idx)%name)) then
         lane%segments(catalog_idx)%name = name
      end if
   end subroutine ensure_lane_timer_metadata

   subroutine ensure_context_storage(segment, required_size)
      type(ftimer_segment_t), intent(inout) :: segment
      integer, intent(in) :: required_size
      integer :: old_size
      integer :: new_size
      real(wp), allocatable :: old_time(:)
      real(wp), allocatable :: old_start_time(:)
      logical, allocatable :: old_is_running(:)
      integer(int64), allocatable :: old_call_count(:)
      integer, allocatable :: old_context_epoch(:)
      integer, allocatable :: old_context_max_worker_lane_count(:)

      if (required_size <= 0) return

      if (allocated(segment%time)) then
         if (size(segment%time) >= required_size) return
         old_size = size(segment%time)
         call move_alloc(segment%time, old_time)
         call move_alloc(segment%start_time, old_start_time)
         call move_alloc(segment%is_running, old_is_running)
         call move_alloc(segment%call_count, old_call_count)
         call move_alloc(segment%context_epoch, old_context_epoch)
         call move_alloc(segment%context_max_worker_lane_count, old_context_max_worker_lane_count)
         new_size = max(required_size, 2*old_size)
         allocate (segment%time(new_size))
         allocate (segment%start_time(new_size))
         allocate (segment%is_running(new_size))
         allocate (segment%call_count(new_size))
         allocate (segment%context_epoch(new_size))
         allocate (segment%context_max_worker_lane_count(new_size))
         segment%time = 0.0_wp
         segment%start_time = 0.0_wp
         segment%is_running = .false.
         segment%call_count = 0_int64
         segment%context_epoch = FTIMER_OPENMP_CONTEXT_EPOCH_UNKNOWN
         segment%context_max_worker_lane_count = 0
         if (old_size > 0) then
            segment%time(1:old_size) = old_time
            segment%start_time(1:old_size) = old_start_time
            segment%is_running(1:old_size) = old_is_running
            segment%call_count(1:old_size) = old_call_count
            segment%context_epoch(1:old_size) = old_context_epoch
            segment%context_max_worker_lane_count(1:old_size) = old_context_max_worker_lane_count
         end if
      else
         new_size = required_size
         allocate (segment%time(new_size))
         allocate (segment%start_time(new_size))
         allocate (segment%is_running(new_size))
         allocate (segment%call_count(new_size))
         allocate (segment%context_epoch(new_size))
         allocate (segment%context_max_worker_lane_count(new_size))
         segment%time = 0.0_wp
         segment%start_time = 0.0_wp
         segment%is_running = .false.
         segment%call_count = 0_int64
         segment%context_epoch = FTIMER_OPENMP_CONTEXT_EPOCH_UNKNOWN
         segment%context_max_worker_lane_count = 0
      end if
   end subroutine ensure_context_storage

   subroutine note_context_epoch(segment, ctx, epoch, worker_lane_count)
      type(ftimer_segment_t), intent(inout) :: segment
      integer, intent(in) :: ctx
      integer, intent(in) :: epoch
      integer, intent(in) :: worker_lane_count

      if ((.not. allocated(segment%context_epoch)) .or. (ctx <= 0) .or. (ctx > size(segment%context_epoch))) return
      if (.not. allocated(segment%context_max_worker_lane_count)) return

      if (segment%call_count(ctx) == 0_int64) then
         segment%context_epoch(ctx) = epoch
      elseif (segment%context_epoch(ctx) /= epoch) then
         segment%context_epoch(ctx) = FTIMER_OPENMP_CONTEXT_EPOCH_UNKNOWN
      end if
      segment%context_max_worker_lane_count(ctx) = max(segment%context_max_worker_lane_count(ctx), worker_lane_count)
   end subroutine note_context_epoch

   logical function normalize_config(config) result(is_valid)
      type(ftimer_openmp_config_t), intent(inout) :: config

      is_valid = .false.

      if (config%mode /= FTIMER_OPENMP_MODE_THREAD_LANES) return
      if (config%max_lanes < 0) return
      if (config%max_worker_diagnostics < 0) return

      if (config%max_lanes == 0) config%max_lanes = default_max_lanes()
      if (config%max_lanes < 1) return

      is_valid = .true.
   end function normalize_config

   integer function default_max_lanes() result(max_lanes)
#ifdef FTIMER_USE_OPENMP
      max_lanes = 1 + omp_get_max_threads()
#else
      max_lanes = 1
#endif
   end function default_max_lanes

   logical function is_inside_parallel_region() result(inside)
#ifdef FTIMER_USE_OPENMP
      inside = omp_in_parallel()
#else
      inside = .false.
#endif
   end function is_inside_parallel_region

   subroutine normalize_name(name, trimmed_len, status, message)
      character(len=*), intent(in) :: name
      integer, intent(out) :: trimmed_len
      integer, intent(out) :: status
      character(len=:), allocatable, intent(out) :: message
      integer :: code
      integer :: i
      character(len=32) :: position_text

      trimmed_len = len_trim(name)

      if (trimmed_len <= 0) then
         status = FTIMER_ERR_INVALID_NAME
         message = "ftimer_openmp timer name must not be empty"
         return
      end if

      if (name(1:1) == ' ') then
         status = FTIMER_ERR_INVALID_NAME
         message = "ftimer_openmp timer name must not begin with whitespace"
         return
      end if

      do i = 1, trimmed_len
         code = iachar(name(i:i))
         if ((code < 32) .or. (code == 127)) then
            status = FTIMER_ERR_INVALID_NAME
            write (position_text, '(i0)') i
            message = "ftimer_openmp timer name contains control character at position "//trim(position_text)
            return
         end if
      end do

      status = FTIMER_SUCCESS
   end subroutine normalize_name

   subroutine ensure_object_token(self)
      class(ftimer_openmp_t), intent(inout) :: self

      if (self%object_token /= 0_int64) return
      if (next_object_token <= 0_int64) return

      self%object_token = next_object_token
      if (next_object_token == huge(next_object_token)) then
         next_object_token = -1_int64
      else
         next_object_token = next_object_token + 1_int64
      end if
   end subroutine ensure_object_token

   integer(int64) function allocate_region_token() result(token)
      token = 0_int64
      if (next_region_token <= 0_int64) return

      token = next_region_token
      if (next_region_token == huge(next_region_token)) then
         next_region_token = -1_int64
      else
         next_region_token = next_region_token + 1_int64
      end if
   end function allocate_region_token

   subroutine ensure_catalog_capacity(self, required_size)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: required_size
      type(ftimer_openmp_catalog_entry_t), allocatable :: old_catalog(:)
      integer :: new_size

      if (allocated(self%catalog)) then
         if (size(self%catalog) >= required_size) return
         call move_alloc(self%catalog, old_catalog)
         new_size = max(required_size, 2*size(old_catalog))
         allocate (self%catalog(new_size))
         if (self%num_timers > 0) self%catalog(1:self%num_timers) = old_catalog(1:self%num_timers)
      else
         new_size = max(required_size, FTIMER_OPENMP_CATALOG_INITIAL_CAPACITY)
         allocate (self%catalog(new_size))
      end if
   end subroutine ensure_catalog_capacity

   subroutine ensure_id_index_capacity(self, required_id)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: required_id
      integer, allocatable :: old_index(:)
      integer :: new_base
      integer :: new_size
      integer :: offset
      integer :: old_base
      integer :: old_size
      integer :: old_upper
      integer :: old_offset

      if (required_id <= 0) return

      if (allocated(self%id_to_catalog_idx)) then
         offset = required_id - self%id_index_base + 1
         if ((offset >= 1) .and. (offset <= size(self%id_to_catalog_idx))) return
         call move_alloc(self%id_to_catalog_idx, old_index)
         old_base = self%id_index_base
         old_size = size(old_index)
         old_upper = old_base + old_size - 1
         new_base = min(required_id, old_base)
         new_size = max(required_id, old_upper) - new_base + 1
         new_size = max(new_size, 2*old_size)
         allocate (self%id_to_catalog_idx(new_size))
         self%id_to_catalog_idx = 0
         if (old_size > 0) then
            old_offset = old_base - new_base + 1
            self%id_to_catalog_idx(old_offset:old_offset + old_size - 1) = old_index
         end if
         self%id_index_base = new_base
      else
         self%id_index_base = required_id
         new_size = FTIMER_OPENMP_CATALOG_INITIAL_CAPACITY
         allocate (self%id_to_catalog_idx(new_size))
         self%id_to_catalog_idx = 0
      end if
   end subroutine ensure_id_index_capacity

   integer function allocate_timer_id(self) result(id)
      class(ftimer_openmp_t), intent(inout) :: self

      if (self%next_timer_id <= 0) then
         id = 0
         return
      end if

      id = self%next_timer_id
      if (self%next_timer_id == huge(self%next_timer_id)) then
         self%next_timer_id = -1
      else
         self%next_timer_id = self%next_timer_id + 1
      end if
   end function allocate_timer_id

   integer function find_timer_index(self, name) result(idx)
      class(ftimer_openmp_t), intent(in) :: self
      character(len=*), intent(in) :: name
      integer :: i

      idx = 0
      if (.not. allocated(self%catalog)) return

      do i = 1, self%num_timers
         if (allocated(self%catalog(i)%name)) then
            if (self%catalog(i)%name == name) then
               idx = i
               return
            end if
         end if
      end do
   end function find_timer_index

   integer function find_timer_id_index(self, id) result(idx)
      class(ftimer_openmp_t), intent(in) :: self
      integer, intent(in) :: id
      integer :: offset

      idx = 0
      if ((id <= 0) .or. (.not. allocated(self%id_to_catalog_idx))) return
      offset = id - self%id_index_base + 1
      if ((offset < 1) .or. (offset > size(self%id_to_catalog_idx))) return

      idx = self%id_to_catalog_idx(offset)
      if ((idx < 1) .or. (idx > self%num_timers)) idx = 0
   end function find_timer_id_index

#ifdef FTIMER_BUILD_SMOKE_TESTS
   subroutine test_set_clock(self, clock, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      procedure(ftimer_clock_func) :: clock
      integer, intent(out), optional :: ierr

      if (self%region_open .or. has_active_lanes(self)) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, "ftimer_openmp test_set_clock with active timing")
         return
      end if

      self%clock => clock
      if (self%initialized) then
         self%init_wtime = openmp_clock(self)
         self%init_date = ftimer_date_string()
      end if
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine test_set_clock

   subroutine test_lane_total_call_count(self, lane_id, id, call_count, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: lane_id
      integer, intent(in) :: id
      integer(int64), intent(out) :: call_count
      integer, intent(out), optional :: ierr
      integer :: catalog_idx
      integer :: ctx
      integer :: lane_idx

      call_count = 0_int64

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp test call count before init")
         return
      end if

      catalog_idx = find_timer_id_index(self, id)
      if (catalog_idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp test call count with unknown timer id")
         return
      end if

      lane_idx = lane_id + 1
      if ((.not. allocated(self%lanes)) .or. (lane_idx < 1) .or. (lane_idx > size(self%lanes))) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp test call count with unknown lane id")
         return
      end if

      if (allocated(self%lanes(lane_idx)%segments)) then
         if (size(self%lanes(lane_idx)%segments) >= catalog_idx) then
            if (allocated(self%lanes(lane_idx)%segments(catalog_idx)%call_count)) then
               do ctx = 1, self%lanes(lane_idx)%segments(catalog_idx)%contexts%count
                  call_count = call_count + self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx)
               end do
            end if
         end if
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine test_lane_total_call_count

   subroutine test_lane_parent_call_count(self, lane_id, id, parent_id, call_count, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: lane_id
      integer, intent(in) :: id
      integer, intent(in) :: parent_id
      integer(int64), intent(out) :: call_count
      integer, intent(out), optional :: ierr
      integer :: catalog_idx
      integer :: ctx
      integer :: lane_idx

      call_count = 0_int64

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp test parent call count before init")
         return
      end if

      catalog_idx = find_timer_id_index(self, id)
      if (catalog_idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, &
                                  "ftimer_openmp test parent call count with unknown timer id")
         return
      end if

      lane_idx = lane_id + 1
      if ((.not. allocated(self%lanes)) .or. (lane_idx < 1) .or. (lane_idx > size(self%lanes))) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, &
                                  "ftimer_openmp test parent call count with unknown lane id")
         return
      end if

      if (allocated(self%lanes(lane_idx)%segments)) then
         if (size(self%lanes(lane_idx)%segments) >= catalog_idx) then
            if (allocated(self%lanes(lane_idx)%segments(catalog_idx)%call_count)) then
               do ctx = 1, self%lanes(lane_idx)%segments(catalog_idx)%contexts%count
                  if (self%lanes(lane_idx)%segments(catalog_idx)%contexts%stacks(ctx)%depth == 1) then
                     if (self%lanes(lane_idx)%segments(catalog_idx)%contexts%stacks(ctx)%ids(1) == parent_id) then
                        call_count = call_count + self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx)
                     end if
                  end if
               end do
            end if
         end if
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine test_lane_parent_call_count

   subroutine test_lane_stack_call_count(self, lane_id, id, parent_ids, call_count, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: lane_id
      integer, intent(in) :: id
      integer, intent(in) :: parent_ids(:)
      integer(int64), intent(out) :: call_count
      integer, intent(out), optional :: ierr
      integer :: catalog_idx
      integer :: ctx
      integer :: lane_idx

      call_count = 0_int64

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp test stack call count before init")
         return
      end if

      catalog_idx = find_timer_id_index(self, id)
      if (catalog_idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, &
                                  "ftimer_openmp test stack call count with unknown timer id")
         return
      end if

      lane_idx = lane_id + 1
      if ((.not. allocated(self%lanes)) .or. (lane_idx < 1) .or. (lane_idx > size(self%lanes))) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, &
                                  "ftimer_openmp test stack call count with unknown lane id")
         return
      end if

      if (allocated(self%lanes(lane_idx)%segments)) then
         if (size(self%lanes(lane_idx)%segments) >= catalog_idx) then
            if (allocated(self%lanes(lane_idx)%segments(catalog_idx)%call_count)) then
               do ctx = 1, self%lanes(lane_idx)%segments(catalog_idx)%contexts%count
                  if (self%lanes(lane_idx)%segments(catalog_idx)%contexts%stacks(ctx)%depth == size(parent_ids)) then
                     if (all(self%lanes(lane_idx)%segments(catalog_idx)%contexts%stacks(ctx)%ids(1:size(parent_ids)) == &
                             parent_ids)) then
                        call_count = call_count + self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx)
                     end if
                  end if
               end do
            end if
         end if
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine test_lane_stack_call_count

   subroutine test_lane_total_time(self, lane_id, id, total_time, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: lane_id
      integer, intent(in) :: id
      real(wp), intent(out) :: total_time
      integer, intent(out), optional :: ierr
      integer :: catalog_idx
      integer :: ctx
      integer :: lane_idx

      total_time = 0.0_wp

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp test total time before init")
         return
      end if

      catalog_idx = find_timer_id_index(self, id)
      if (catalog_idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp test total time with unknown timer id")
         return
      end if

      lane_idx = lane_id + 1
      if ((.not. allocated(self%lanes)) .or. (lane_idx < 1) .or. (lane_idx > size(self%lanes))) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp test total time with unknown lane id")
         return
      end if

      if (allocated(self%lanes(lane_idx)%segments)) then
         if (size(self%lanes(lane_idx)%segments) >= catalog_idx) then
            if (allocated(self%lanes(lane_idx)%segments(catalog_idx)%time)) then
               do ctx = 1, self%lanes(lane_idx)%segments(catalog_idx)%contexts%count
                  total_time = total_time + self%lanes(lane_idx)%segments(catalog_idx)%time(ctx)
               end do
            end if
         end if
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine test_lane_total_time

   subroutine test_lane_parent_total_time(self, lane_id, id, parent_id, total_time, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: lane_id
      integer, intent(in) :: id
      integer, intent(in) :: parent_id
      real(wp), intent(out) :: total_time
      integer, intent(out), optional :: ierr
      integer :: catalog_idx
      integer :: ctx
      integer :: lane_idx

      total_time = 0.0_wp

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp test parent total time before init")
         return
      end if

      catalog_idx = find_timer_id_index(self, id)
      if (catalog_idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, &
                                  "ftimer_openmp test parent total time with unknown timer id")
         return
      end if

      lane_idx = lane_id + 1
      if ((.not. allocated(self%lanes)) .or. (lane_idx < 1) .or. (lane_idx > size(self%lanes))) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, &
                                  "ftimer_openmp test parent total time with unknown lane id")
         return
      end if

      if (allocated(self%lanes(lane_idx)%segments)) then
         if (size(self%lanes(lane_idx)%segments) >= catalog_idx) then
            if (allocated(self%lanes(lane_idx)%segments(catalog_idx)%time)) then
               do ctx = 1, self%lanes(lane_idx)%segments(catalog_idx)%contexts%count
                  if (self%lanes(lane_idx)%segments(catalog_idx)%contexts%stacks(ctx)%depth == 1) then
                     if (self%lanes(lane_idx)%segments(catalog_idx)%contexts%stacks(ctx)%ids(1) == parent_id) then
                        total_time = total_time + self%lanes(lane_idx)%segments(catalog_idx)%time(ctx)
                     end if
                  end if
               end do
            end if
         end if
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine test_lane_parent_total_time

   subroutine test_lane_stack_total_time(self, lane_id, id, parent_ids, total_time, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: lane_id
      integer, intent(in) :: id
      integer, intent(in) :: parent_ids(:)
      real(wp), intent(out) :: total_time
      integer, intent(out), optional :: ierr
      integer :: catalog_idx
      integer :: ctx
      integer :: lane_idx

      total_time = 0.0_wp

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp test stack total time before init")
         return
      end if

      catalog_idx = find_timer_id_index(self, id)
      if (catalog_idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, &
                                  "ftimer_openmp test stack total time with unknown timer id")
         return
      end if

      lane_idx = lane_id + 1
      if ((.not. allocated(self%lanes)) .or. (lane_idx < 1) .or. (lane_idx > size(self%lanes))) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, &
                                  "ftimer_openmp test stack total time with unknown lane id")
         return
      end if

      if (allocated(self%lanes(lane_idx)%segments)) then
         if (size(self%lanes(lane_idx)%segments) >= catalog_idx) then
            if (allocated(self%lanes(lane_idx)%segments(catalog_idx)%time)) then
               do ctx = 1, self%lanes(lane_idx)%segments(catalog_idx)%contexts%count
                  if (self%lanes(lane_idx)%segments(catalog_idx)%contexts%stacks(ctx)%depth == size(parent_ids)) then
                     if (all(self%lanes(lane_idx)%segments(catalog_idx)%contexts%stacks(ctx)%ids(1:size(parent_ids)) == &
                             parent_ids)) then
                        total_time = total_time + self%lanes(lane_idx)%segments(catalog_idx)%time(ctx)
                     end if
                  end if
               end do
            end if
         end if
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine test_lane_stack_total_time

   subroutine test_lane_is_running(self, lane_id, id, is_running, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: lane_id
      integer, intent(in) :: id
      logical, intent(out) :: is_running
      integer, intent(out), optional :: ierr
      integer :: catalog_idx
      integer :: ctx
      integer :: lane_idx

      is_running = .false.

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp test running state before init")
         return
      end if

      catalog_idx = find_timer_id_index(self, id)
      if (catalog_idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp test running state with unknown timer id")
         return
      end if

      lane_idx = lane_id + 1
      if ((.not. allocated(self%lanes)) .or. (lane_idx < 1) .or. (lane_idx > size(self%lanes))) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp test running state with unknown lane id")
         return
      end if

      if (allocated(self%lanes(lane_idx)%segments)) then
         if (size(self%lanes(lane_idx)%segments) >= catalog_idx) then
            if (allocated(self%lanes(lane_idx)%segments(catalog_idx)%is_running)) then
               do ctx = 1, self%lanes(lane_idx)%segments(catalog_idx)%contexts%count
                  if (self%lanes(lane_idx)%segments(catalog_idx)%is_running(ctx)) then
                     is_running = .true.
                     exit
                  end if
               end do
            end if
         end if
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine test_lane_is_running
#endif

   subroutine clear_worker_diagnostics(self)
      class(ftimer_openmp_t), intent(inout) :: self

      self%queued_worker_diagnostics = 0
      self%worker_diagnostic_overflow = 0
      self%first_worker_status = FTIMER_SUCCESS
   end subroutine clear_worker_diagnostics

   integer function worker_diagnostic_status(self) result(status)
      class(ftimer_openmp_t), intent(in) :: self

      if ((self%queued_worker_diagnostics <= 0) .and. (self%worker_diagnostic_overflow <= 0)) then
         status = FTIMER_SUCCESS
      elseif (self%first_worker_status /= FTIMER_SUCCESS) then
         status = self%first_worker_status
      else
         status = FTIMER_ERR_UNKNOWN
      end if
   end function worker_diagnostic_status

   logical function drain_worker_diagnostics(self, ierr) result(did_drain_with_ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

      did_drain_with_ierr = .false.
      if ((self%queued_worker_diagnostics <= 0) .and. (self%worker_diagnostic_overflow <= 0)) return

      if (present(ierr)) then
         ierr = worker_diagnostic_status(self)
         call clear_worker_diagnostics(self)
         did_drain_with_ierr = .true.
      else
         call emit_worker_diagnostics(self)
      end if
   end function drain_worker_diagnostics

   logical function drain_worker_diagnostics_silently(self, ierr) result(did_drain_with_ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

      did_drain_with_ierr = .false.
      if ((self%queued_worker_diagnostics <= 0) .and. (self%worker_diagnostic_overflow <= 0)) return

      if (present(ierr)) ierr = worker_diagnostic_status(self)
      call clear_worker_diagnostics(self)
      did_drain_with_ierr = .true.
   end function drain_worker_diagnostics_silently

   subroutine queue_worker_diagnostic(self, code)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: code

#ifdef FTIMER_USE_OPENMP
!$omp critical(ftimer_openmp_worker_diagnostics)
#endif
      if (self%first_worker_status == FTIMER_SUCCESS) self%first_worker_status = code
      if (self%queued_worker_diagnostics < self%config%max_worker_diagnostics) then
         self%queued_worker_diagnostics = self%queued_worker_diagnostics + 1
      else
         self%worker_diagnostic_overflow = self%worker_diagnostic_overflow + 1
      end if
#ifdef FTIMER_USE_OPENMP
!$omp end critical(ftimer_openmp_worker_diagnostics)
#endif
   end subroutine queue_worker_diagnostic

   subroutine emit_worker_diagnostics(self)
      class(ftimer_openmp_t), intent(inout) :: self

      if ((self%queued_worker_diagnostics <= 0) .and. (self%worker_diagnostic_overflow <= 0)) return

      write (error_unit, '(a,i0,a,i0,a,i0)') "ftimer_openmp recorded ", &
         self%queued_worker_diagnostics, " worker diagnostics; first status ", &
         self%first_worker_status, ", overflow ", self%worker_diagnostic_overflow
      call clear_worker_diagnostics(self)
   end subroutine emit_worker_diagnostics

   subroutine report_timer_status(self, ierr, code, message)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr
      integer, intent(in) :: code
      character(len=*), intent(in) :: message

      if (present(ierr)) then
         ierr = code
      elseif (is_inside_parallel_region()) then
         call queue_worker_diagnostic(self, code)
      else
         call emit_worker_diagnostics(self)
         write (error_unit, '(a)') trim(message)
      end if
   end subroutine report_timer_status

end module ftimer_openmp
