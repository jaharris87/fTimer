module ftimer_openmp
   use, intrinsic :: iso_fortran_env, only: error_unit, int64, iostat_end, output_unit
   use ftimer_clock, only: ftimer_date_string, ftimer_default_clock
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_INVALID_NAME, FTIMER_ERR_IO, FTIMER_ERR_MISMATCH, &
                           FTIMER_ERR_NOT_INIT, FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS, &
                           ftimer_call_stack_t, ftimer_clock_func, ftimer_metadata_t, ftimer_segment_t, wp
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Comm, MPI_COMM_WORLD
#endif
#ifdef FTIMER_USE_OPENMP
   use omp_lib, only: omp_get_level, omp_get_max_threads, omp_get_num_threads, omp_get_thread_num, omp_in_parallel
#endif
   implicit none
   private

   public :: FTIMER_OPENMP_MODE_THREAD_LANES
   public :: ftimer_openmp_config_t
   public :: ftimer_openmp_parallel_region_t
   public :: ftimer_openmp_summary_entry_t
   public :: ftimer_openmp_summary_t
   public :: ftimer_openmp_t

   integer, parameter :: FTIMER_OPENMP_MODE_THREAD_LANES = 1
   integer, parameter :: FTIMER_OPENMP_CATALOG_INITIAL_CAPACITY = 16
   integer, parameter :: FTIMER_OPENMP_DEFAULT_WORKER_DIAGNOSTICS = 32
   integer, parameter :: FTIMER_OPENMP_CONTEXT_EPOCH_UNKNOWN = -1
   character(len=*), parameter :: FTIMER_OPENMP_CSV_FORMAT_VERSION = '1'
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
      type(MPI_Comm) :: mpi_comm
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
