module ftimer_openmp
   use, intrinsic :: iso_fortran_env, only: error_unit, int64
   use ftimer_clock, only: ftimer_default_clock
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_INVALID_NAME, FTIMER_ERR_MISMATCH, &
                           FTIMER_ERR_NOT_INIT, FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS, &
                           ftimer_call_stack_t, ftimer_segment_t, wp
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Comm, MPI_COMM_WORLD
#endif
#ifdef FTIMER_USE_OPENMP
   use omp_lib, only: omp_get_level, omp_get_max_threads, omp_get_thread_num, omp_in_parallel
#endif
   implicit none
   private

   public :: FTIMER_OPENMP_MODE_THREAD_LANES
   public :: ftimer_openmp_config_t
   public :: ftimer_openmp_parallel_region_t
   public :: ftimer_openmp_t

   integer, parameter :: FTIMER_OPENMP_MODE_THREAD_LANES = 1
   integer, parameter :: FTIMER_OPENMP_CATALOG_INITIAL_CAPACITY = 16
   integer, parameter :: FTIMER_OPENMP_DEFAULT_WORKER_DIAGNOSTICS = 32

   type :: ftimer_openmp_config_t
      integer :: mode = FTIMER_OPENMP_MODE_THREAD_LANES
      integer :: max_lanes = 0
      integer :: max_worker_diagnostics = FTIMER_OPENMP_DEFAULT_WORKER_DIAGNOSTICS
   end type ftimer_openmp_config_t

   type :: ftimer_openmp_parallel_region_t
      private
      integer :: epoch = 0
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

   type :: ftimer_openmp_t
      private
      logical :: initialized = .false.
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_catalog_entry_t), allocatable :: catalog(:)
      integer, allocatable :: id_to_catalog_idx(:)
      type(ftimer_openmp_lane_t), allocatable :: lanes(:)
      integer :: num_timers = 0
      integer :: next_timer_id = 1
      logical :: region_open = .false.
      integer :: current_epoch = 0
      integer :: next_epoch = 1
      integer :: queued_worker_diagnostics = 0
      integer :: worker_diagnostic_overflow = 0
      integer :: first_worker_status = FTIMER_SUCCESS
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
#ifdef FTIMER_BUILD_SMOKE_TESTS
      procedure :: test_lane_total_call_count
      procedure :: test_lane_parent_call_count
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
      integer :: lifecycle_status

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

      lifecycle_status = worker_diagnostic_status(self)
      if (.not. present(ierr)) call emit_worker_diagnostics(self)
      call clear_state(self)
      self%initialized = .true.
      self%config = effective_config
      call allocate_lanes(self)
#ifdef FTIMER_USE_MPI
      self%mpi_comm = MPI_COMM_WORLD
      self%mpi_comm_was_present = .false.
      if (present(comm)) then
         self%mpi_comm = comm
         self%mpi_comm_was_present = .true.
      end if
#endif

      if (present(ierr)) ierr = lifecycle_status
   end subroutine init_impl

   subroutine finalize(self, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr
      integer :: lifecycle_status

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

      lifecycle_status = worker_diagnostic_status(self)
      if (.not. present(ierr)) call emit_worker_diagnostics(self)
      call clear_state(self)
      if (present(ierr)) ierr = lifecycle_status
   end subroutine finalize

   subroutine reset(self, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr
      type(ftimer_openmp_config_t) :: saved_config
      integer :: lifecycle_status
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
      lifecycle_status = worker_diagnostic_status(self)
      if (.not. present(ierr)) call emit_worker_diagnostics(self)
      self%initialized = .true.
      self%config = saved_config
      self%region_open = .false.
      self%current_epoch = 0
      self%next_epoch = 1
      call clear_all_lanes(self)
      call clear_worker_diagnostics(self)
#ifdef FTIMER_USE_MPI
      self%mpi_comm = saved_mpi_comm
      self%mpi_comm_was_present = saved_mpi_comm_was_present
#endif
      if (present(ierr)) ierr = lifecycle_status
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
      self%id_to_catalog_idx(id) = self%num_timers
      call ensure_all_lane_segment_capacity(self, self%num_timers)

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

      if (has_active_lanes(self)) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp begin_parallel_region with active lane timers")
         return
      end if

      self%region_open = .true.
      self%current_epoch = self%next_epoch
      if (self%next_epoch < huge(self%next_epoch)) self%next_epoch = self%next_epoch + 1
      region%epoch = self%current_epoch
      region%active = .true.
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine begin_parallel_region

   subroutine end_parallel_region(self, region, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_parallel_region_t), intent(inout) :: region
      integer, intent(out), optional :: ierr

      if (.not. self%initialized) then
         call clear_region(region)
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp end_parallel_region before init")
         return
      end if

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp end_parallel_region called inside an OpenMP parallel region")
         return
      end if

      if ((.not. self%region_open) .or. (.not. region%active) .or. (region%epoch /= self%current_epoch)) then
         call clear_region(region)
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp end_parallel_region without matching open timed region")
         return
      end if

      if (has_active_lanes(self)) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp end_parallel_region with active lane timers")
         return
      end if

      self%region_open = .false.
      self%current_epoch = 0
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

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp start_id before init")
         return
      end if

      catalog_idx = find_timer_id_index(self, id)
      if (catalog_idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp start_id with unknown timer id")
         return
      end if

      status = resolve_timing_lane(self, lane_idx, epoch)
      if (status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, status, "ftimer_openmp start_id outside a valid timed lane")
         return
      end if

      call start_lane_timer(self, lane_idx, catalog_idx, id, epoch, ierr)
   end subroutine start_id

   subroutine stop_id(self, id, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr
      integer :: catalog_idx
      integer :: epoch
      integer :: lane_idx
      integer :: status

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp stop_id before init")
         return
      end if

      catalog_idx = find_timer_id_index(self, id)
      if (catalog_idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp stop_id with unknown timer id")
         return
      end if

      status = resolve_timing_lane(self, lane_idx, epoch)
      if (status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, status, "ftimer_openmp stop_id outside a valid timed lane")
         return
      end if

      call stop_lane_timer(self, lane_idx, catalog_idx, id, epoch, ierr)
   end subroutine stop_id

   subroutine clear_state(self)
      class(ftimer_openmp_t), intent(inout) :: self

      self%initialized = .false.
      self%config = ftimer_openmp_config_t()
      if (allocated(self%catalog)) deallocate (self%catalog)
      if (allocated(self%id_to_catalog_idx)) deallocate (self%id_to_catalog_idx)
      if (allocated(self%lanes)) deallocate (self%lanes)
      self%num_timers = 0
      self%region_open = .false.
      self%current_epoch = 0
      self%next_epoch = 1
      call clear_worker_diagnostics(self)
#ifdef FTIMER_USE_MPI
      self%mpi_comm_was_present = .false.
#endif
   end subroutine clear_state

   subroutine clear_region(region)
      type(ftimer_openmp_parallel_region_t), intent(inout) :: region

      region%epoch = 0
      region%active = .false.
   end subroutine clear_region

   subroutine allocate_lanes(self)
      class(ftimer_openmp_t), intent(inout) :: self
      integer :: i

      if (allocated(self%lanes)) deallocate (self%lanes)
      allocate (self%lanes(self%config%max_lanes))
      do i = 1, size(self%lanes)
         self%lanes(i)%lane_id = i - 1
         self%lanes(i)%participated = .false.
         call ensure_lane_segment_capacity(self%lanes(i), self%num_timers)
      end do
   end subroutine allocate_lanes

   subroutine clear_all_lanes(self)
      class(ftimer_openmp_t), intent(inout) :: self

      call allocate_lanes(self)
      call ensure_all_lane_segment_capacity(self, self%num_timers)
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

   integer function resolve_timing_lane(self, lane_idx, epoch) result(status)
      class(ftimer_openmp_t), intent(in) :: self
      integer, intent(out) :: lane_idx
      integer, intent(out) :: epoch
      integer :: lane_id

      lane_id = current_lane_id()
      lane_idx = lane_id + 1
      epoch = 0

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

   subroutine start_lane_timer(self, lane_idx, catalog_idx, timer_id, epoch, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: lane_idx
      integer, intent(in) :: catalog_idx
      integer, intent(in) :: timer_id
      integer, intent(in) :: epoch
      integer, intent(out), optional :: ierr
      integer :: ctx

      call ensure_lane_segment_capacity(self%lanes(lane_idx), self%num_timers)
      call ensure_lane_timer_metadata(self%lanes(lane_idx), catalog_idx, self%catalog(catalog_idx)%name)

      ctx = self%lanes(lane_idx)%segments(catalog_idx)%contexts%find(self%lanes(lane_idx)%call_stack)
      if (ctx <= 0) ctx = self%lanes(lane_idx)%segments(catalog_idx)%contexts%add(self%lanes(lane_idx)%call_stack)
      call ensure_context_storage(self%lanes(lane_idx)%segments(catalog_idx), ctx)

      if (self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx) == &
          huge(self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx))) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp start_id call count overflow")
         return
      end if

      self%lanes(lane_idx)%participated = .true.
      self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx) = &
         self%lanes(lane_idx)%segments(catalog_idx)%call_count(ctx) + 1_int64
      self%lanes(lane_idx)%segments(catalog_idx)%is_running(ctx) = .true.
      self%lanes(lane_idx)%segments(catalog_idx)%start_time(ctx) = ftimer_default_clock()
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

      now = ftimer_default_clock()
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

   subroutine ensure_all_lane_segment_capacity(self, required_size)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: required_size
      integer :: i

      if (.not. allocated(self%lanes)) return
      do i = 1, size(self%lanes)
         call ensure_lane_segment_capacity(self%lanes(i), required_size)
      end do
   end subroutine ensure_all_lane_segment_capacity

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

      if (required_size <= 0) return

      if (allocated(segment%time)) then
         if (size(segment%time) >= required_size) return
         old_size = size(segment%time)
         call move_alloc(segment%time, old_time)
         call move_alloc(segment%start_time, old_start_time)
         call move_alloc(segment%is_running, old_is_running)
         call move_alloc(segment%call_count, old_call_count)
         new_size = max(required_size, 2*old_size)
         allocate (segment%time(new_size))
         allocate (segment%start_time(new_size))
         allocate (segment%is_running(new_size))
         allocate (segment%call_count(new_size))
         segment%time = 0.0_wp
         segment%start_time = 0.0_wp
         segment%is_running = .false.
         segment%call_count = 0_int64
         if (old_size > 0) then
            segment%time(1:old_size) = old_time
            segment%start_time(1:old_size) = old_start_time
            segment%is_running(1:old_size) = old_is_running
            segment%call_count(1:old_size) = old_call_count
         end if
      else
         new_size = required_size
         allocate (segment%time(new_size))
         allocate (segment%start_time(new_size))
         allocate (segment%is_running(new_size))
         allocate (segment%call_count(new_size))
         segment%time = 0.0_wp
         segment%start_time = 0.0_wp
         segment%is_running = .false.
         segment%call_count = 0_int64
      end if
   end subroutine ensure_context_storage

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
      integer :: new_size

      if (required_id <= 0) return

      if (allocated(self%id_to_catalog_idx)) then
         if (size(self%id_to_catalog_idx) >= required_id) return
         call move_alloc(self%id_to_catalog_idx, old_index)
         new_size = max(required_id, 2*size(old_index))
         allocate (self%id_to_catalog_idx(new_size))
         self%id_to_catalog_idx = 0
         if (size(old_index) > 0) self%id_to_catalog_idx(1:size(old_index)) = old_index
      else
         new_size = max(required_id, FTIMER_OPENMP_CATALOG_INITIAL_CAPACITY)
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

      idx = 0
      if ((id <= 0) .or. (.not. allocated(self%id_to_catalog_idx))) return
      if (id > size(self%id_to_catalog_idx)) return

      idx = self%id_to_catalog_idx(id)
      if ((idx < 1) .or. (idx > self%num_timers)) idx = 0
   end function find_timer_id_index

#ifdef FTIMER_BUILD_SMOKE_TESTS
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
