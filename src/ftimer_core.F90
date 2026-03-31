module ftimer_core
   use, intrinsic :: iso_c_binding, only: c_null_ptr, c_ptr
   use, intrinsic :: iso_fortran_env, only: error_unit
   use ftimer_clock, only: ftimer_date_string, ftimer_default_clock, ftimer_mpi_clock
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_IO, FTIMER_ERR_INVALID_NAME, FTIMER_ERR_MISMATCH, &
                           FTIMER_ERR_NOT_INIT, FTIMER_ERR_UNKNOWN, FTIMER_EVENT_START, FTIMER_EVENT_STOP, &
                           FTIMER_MISMATCH_REPAIR, FTIMER_MISMATCH_STRICT, FTIMER_MISMATCH_WARN, FTIMER_NAME_LEN, &
                           FTIMER_SUCCESS, ftimer_call_stack_t, ftimer_clock_func, ftimer_hook_proc, &
                           ftimer_metadata_t, ftimer_mpi_summary_t, ftimer_segment_t, ftimer_summary_t, wp
   implicit none
   private

   public :: ftimer_t
#ifdef FTIMER_BUILD_TESTS
   public :: ftimer_test_get_state
   public :: ftimer_test_state_t
#endif

#ifdef FTIMER_BUILD_TESTS
   type :: ftimer_test_state_t
      type(ftimer_call_stack_t) :: call_stack
      type(ftimer_segment_t), allocatable :: segments(:)
      integer :: num_segments = 0
      real(wp) :: init_wtime = 0.0_wp
      character(len=40) :: init_date = ''
      logical :: initialized = .false.
      integer :: mismatch_mode = FTIMER_MISMATCH_STRICT
#ifdef FTIMER_USE_MPI
      integer :: mpi_comm = -1
      integer :: mpi_rank = -1
      integer :: mpi_nprocs = 1
#endif
   end type ftimer_test_state_t
#endif

   type :: ftimer_t
      private
      type(ftimer_call_stack_t) :: call_stack
      type(ftimer_segment_t), allocatable :: segments(:)
      integer :: num_segments = 0
      real(wp) :: init_wtime = 0.0_wp
      character(len=40) :: init_date = ''
      logical :: initialized = .false.
      integer :: mismatch_mode = FTIMER_MISMATCH_STRICT
#ifdef FTIMER_USE_MPI
      integer :: mpi_comm = -1
      integer :: mpi_rank = -1
      integer :: mpi_nprocs = 1
#endif
      procedure(ftimer_clock_func), pointer, nopass :: clock => null()
      procedure(ftimer_hook_proc), pointer, nopass :: on_event => null()
      type(c_ptr) :: user_data = c_null_ptr
   contains
      procedure :: init
      procedure :: finalize
      procedure :: set_clock
      procedure :: clear_clock
      procedure :: set_callback
      procedure :: clear_callback
      procedure :: start
      procedure :: stop
      procedure :: start_id
      procedure :: stop_id
      procedure :: lookup
      procedure :: reset
      procedure :: get_summary
      procedure :: mpi_summary
      procedure :: print_summary
      procedure :: write_summary
      procedure :: print_mpi_summary
      procedure :: write_mpi_summary
      procedure, private :: wtime
      procedure, private :: find_or_create_segment
      procedure, private :: repair_mismatch
   end type ftimer_t

   interface
      module subroutine get_summary(self, summary, ierr)
         class(ftimer_t), intent(in) :: self
         type(ftimer_summary_t), intent(out) :: summary
         integer, intent(out), optional :: ierr
      end subroutine get_summary

      module subroutine mpi_summary(self, summary, ierr)
         class(ftimer_t), intent(in) :: self
         type(ftimer_mpi_summary_t), intent(out) :: summary
         integer, intent(out), optional :: ierr
      end subroutine mpi_summary

      module subroutine print_summary(self, unit, metadata, ierr)
         class(ftimer_t), intent(in) :: self
         integer, intent(in), optional :: unit
         type(ftimer_metadata_t), intent(in), optional :: metadata(:)
         integer, intent(out), optional :: ierr
      end subroutine print_summary

      module subroutine write_summary(self, filename, append, metadata, ierr)
         class(ftimer_t), intent(in) :: self
         character(len=*), intent(in) :: filename
         logical, intent(in), optional :: append
         type(ftimer_metadata_t), intent(in), optional :: metadata(:)
         integer, intent(out), optional :: ierr
      end subroutine write_summary

      module subroutine print_mpi_summary(self, unit, metadata, ierr)
         class(ftimer_t), intent(in) :: self
         integer, intent(in), optional :: unit
         type(ftimer_metadata_t), intent(in), optional :: metadata(:)
         integer, intent(out), optional :: ierr
      end subroutine print_mpi_summary

      module subroutine write_mpi_summary(self, filename, append, metadata, ierr)
         class(ftimer_t), intent(in) :: self
         character(len=*), intent(in) :: filename
         logical, intent(in), optional :: append
         type(ftimer_metadata_t), intent(in), optional :: metadata(:)
         integer, intent(out), optional :: ierr
      end subroutine write_mpi_summary
   end interface

contains

   subroutine init(self, comm, mismatch_mode, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in), optional :: comm
      integer, intent(in), optional :: mismatch_mode
      integer, intent(out), optional :: ierr

      ! Contract: ierr is last to eliminate the positional intent(out) trap.
      ! A single positional integer now binds to comm (intent(in)), not ierr.
      ! Keywords are recommended for readability.
      !$omp master
      call init_impl(self, ierr=ierr, comm=comm, mismatch_mode=mismatch_mode)
!$omp end master
   end subroutine init

   subroutine init_impl(self, comm, mismatch_mode, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in), optional :: comm
      integer, intent(in), optional :: mismatch_mode
      integer, intent(out), optional :: ierr

      if (present(mismatch_mode)) then
         select case (mismatch_mode)
         case (FTIMER_MISMATCH_STRICT, FTIMER_MISMATCH_WARN, FTIMER_MISMATCH_REPAIR)
         case default
            call report_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer init with invalid mismatch mode")
            return
         end select
      end if

      if (self%initialized .and. has_active_timers(self)) then
         call report_status(ierr, FTIMER_ERR_ACTIVE, "ftimer init with active timers; state unchanged")
         return
      end if

      call clear_runtime_state(self, keep_hooks=.true.)
      self%initialized = .true.

      if (present(mismatch_mode)) then
         self%mismatch_mode = mismatch_mode
      else
         self%mismatch_mode = FTIMER_MISMATCH_STRICT
      end if

#ifdef FTIMER_USE_MPI
      if (present(comm)) then
         self%mpi_comm = comm
      else
         self%mpi_comm = -1
      end if
      self%mpi_rank = -1
      self%mpi_nprocs = 1
#endif
      if (.not. associated(self%clock)) call restore_default_clock(self)
      self%init_wtime = self%wtime()
      self%init_date = ftimer_date_string()

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine init_impl

   subroutine finalize(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

!$omp master
      call finalize_impl(self, ierr=ierr)
!$omp end master
   end subroutine finalize

   subroutine finalize_impl(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

      if (.not. self%initialized) then
         if (present(ierr)) ierr = FTIMER_SUCCESS
         return
      end if

      if (has_active_timers(self)) then
         call report_status(ierr, FTIMER_ERR_ACTIVE, "ftimer finalize with active timers; state unchanged")
         return
      end if

      call clear_runtime_state(self, keep_hooks=.false.)
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine finalize_impl

   subroutine set_clock(self, clock, ierr)
      class(ftimer_t), intent(inout) :: self
      procedure(ftimer_clock_func) :: clock
      integer, intent(out), optional :: ierr

!$omp master
      call set_clock_impl(self, clock, ierr=ierr)
!$omp end master
   end subroutine set_clock

   subroutine set_clock_impl(self, clock, ierr)
      class(ftimer_t), intent(inout) :: self
      procedure(ftimer_clock_func) :: clock
      integer, intent(out), optional :: ierr

      if (.not. can_configure_clock(self)) then
         call report_status(ierr, FTIMER_ERR_ACTIVE, "ftimer set_clock after timing has started; state unchanged")
         return
      end if

      self%clock => clock
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine set_clock_impl

   subroutine clear_clock(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

!$omp master
      call clear_clock_impl(self, ierr=ierr)
!$omp end master
   end subroutine clear_clock

   subroutine clear_clock_impl(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

      if (.not. can_configure_clock(self)) then
         call report_status(ierr, FTIMER_ERR_ACTIVE, "ftimer clear_clock after timing has started; state unchanged")
         return
      end if

      call restore_default_clock(self)
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine clear_clock_impl

   subroutine set_callback(self, on_event, user_data, ierr)
      class(ftimer_t), intent(inout) :: self
      procedure(ftimer_hook_proc) :: on_event
      type(c_ptr), intent(in), optional :: user_data
      integer, intent(out), optional :: ierr

!$omp master
      call set_callback_impl(self, on_event, user_data=user_data, ierr=ierr)
!$omp end master
   end subroutine set_callback

   subroutine set_callback_impl(self, on_event, user_data, ierr)
      class(ftimer_t), intent(inout) :: self
      procedure(ftimer_hook_proc) :: on_event
      type(c_ptr), intent(in), optional :: user_data
      integer, intent(out), optional :: ierr

      if (has_active_timers(self)) then
         call report_status(ierr, FTIMER_ERR_ACTIVE, "ftimer set_callback with active timers; state unchanged")
         return
      end if

      self%on_event => on_event
      if (present(user_data)) then
         self%user_data = user_data
      else
         self%user_data = c_null_ptr
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine set_callback_impl

   subroutine clear_callback(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

!$omp master
      call clear_callback_impl(self, ierr=ierr)
!$omp end master
   end subroutine clear_callback

   subroutine clear_callback_impl(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

      if (has_active_timers(self)) then
         call report_status(ierr, FTIMER_ERR_ACTIVE, "ftimer clear_callback with active timers; state unchanged")
         return
      end if

      nullify (self%on_event)
      self%user_data = c_null_ptr
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine clear_callback_impl

   subroutine start(self, name, ierr)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

!$omp master
      call start_impl(self, name, ierr=ierr)
!$omp end master
   end subroutine start

   subroutine start_impl(self, name, ierr)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr
      integer :: id
      integer :: status
      character(len=FTIMER_NAME_LEN) :: normalized_name
      character(len=160) :: message

      if (.not. self%initialized) then
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer start before init")
         return
      end if

      call normalize_name(name, normalized_name, status, message)
      if (status /= FTIMER_SUCCESS) then
         call report_status(ierr, status, message)
         return
      end if

      id = self%find_or_create_segment(normalized_name)
      call start_id_impl(self, id, ierr=ierr)
   end subroutine start_impl

   subroutine stop(self, name, ierr)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

!$omp master
      call stop_impl(self, name, ierr=ierr)
!$omp end master
   end subroutine stop

   subroutine stop_impl(self, name, ierr)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr
      integer :: id
      integer :: status
      character(len=FTIMER_NAME_LEN) :: normalized_name
      character(len=160) :: message

      if (.not. self%initialized) then
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer stop before init")
         return
      end if

      call normalize_name(name, normalized_name, status, message)
      if (status /= FTIMER_SUCCESS) then
         call report_status(ierr, status, message)
         return
      end if

      id = find_segment_index(self, normalized_name)
      if (id <= 0) then
         write (message, '(3a)') "ftimer stop on unknown timer: ", trim(normalized_name), ""
         call report_status(ierr, FTIMER_ERR_UNKNOWN, trim(message))
         return
      end if

      call stop_id_impl(self, id, ierr=ierr)
   end subroutine stop_impl

   subroutine start_id(self, id, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr

!$omp master
      call start_id_impl(self, id, ierr=ierr)
!$omp end master
   end subroutine start_id

   subroutine start_id_impl(self, id, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr
      integer :: ctx
      real(wp) :: now

      if (.not. self%initialized) then
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer start_id before init")
         return
      end if

      if ((id < 1) .or. (id > self%num_segments)) then
         call report_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer start_id with unknown timer id")
         return
      end if

      ctx = self%segments(id)%contexts%find(self%call_stack)
      if (ctx <= 0) then
         ctx = self%segments(id)%contexts%add(self%call_stack)
      end if
      call ensure_context_storage(self%segments(id), ctx)

      call self%call_stack%push(id)
      now = self%wtime()
      if (needs_init_wtime_rebase(self)) self%init_wtime = now
      self%segments(id)%start_time(ctx) = now
      self%segments(id)%call_count(ctx) = self%segments(id)%call_count(ctx) + 1
      self%segments(id)%is_running(ctx) = .true.

      if (associated(self%on_event)) then
         call self%on_event(id, ctx, FTIMER_EVENT_START, now, self%user_data)
      end if

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine start_id_impl

   subroutine stop_id(self, id, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr

!$omp master
      call stop_id_impl(self, id, ierr=ierr)
!$omp end master
   end subroutine stop_id

   subroutine stop_id_impl(self, id, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr
      character(len=192) :: message

      if (.not. self%initialized) then
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer stop_id before init")
         return
      end if

      if ((id < 1) .or. (id > self%num_segments)) then
         call report_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer stop_id with unknown timer id")
         return
      end if

      if (self%call_stack%depth <= 0) then
         call report_status(ierr, FTIMER_ERR_MISMATCH, "ftimer stop mismatch on empty call stack")
         return
      end if

      if (self%call_stack%top() == id) then
         call stop_segment_with_now(self, id, self%wtime(), fire_callback=.true.)
         if (present(ierr)) ierr = FTIMER_SUCCESS
         return
      end if

      write (message, '(5a)') "ftimer stop mismatch: requested ", trim(self%segments(id)%name), &
         " but top of stack is ", trim(self%segments(self%call_stack%top())%name), ""

      select case (self%mismatch_mode)
      case (FTIMER_MISMATCH_STRICT)
         call report_status(ierr, FTIMER_ERR_MISMATCH, trim(message))
         return
      case (FTIMER_MISMATCH_WARN)
         if (.not. stack_contains(self%call_stack, id)) then
            call report_status(ierr, FTIMER_ERR_MISMATCH, trim(message))
            return
         end if

         call report_status(ierr, FTIMER_ERR_MISMATCH, trim(message))
         call self%repair_mismatch(id)
      case (FTIMER_MISMATCH_REPAIR)
         if (.not. stack_contains(self%call_stack, id)) then
            call report_status(ierr, FTIMER_ERR_MISMATCH, trim(message))
            return
         end if

         call self%repair_mismatch(id)
         if (present(ierr)) ierr = FTIMER_SUCCESS
      case default
         call report_status(ierr, FTIMER_ERR_MISMATCH, trim(message))
         return
      end select
   end subroutine stop_id_impl

   integer function lookup(self, name, ierr) result(id)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      id = 0
!$omp master
      id = lookup_impl(self, name, ierr)
!$omp end master
   end function lookup

   integer function lookup_impl(self, name, ierr) result(id)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr
      integer :: status
      character(len=FTIMER_NAME_LEN) :: normalized_name
      character(len=160) :: message

      id = 0
      if (.not. self%initialized) then
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer lookup before init")
         return
      end if

      call normalize_name(name, normalized_name, status, message)
      if (status /= FTIMER_SUCCESS) then
         call report_status(ierr, status, message)
         return
      end if

      id = self%find_or_create_segment(normalized_name)
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end function lookup_impl

   subroutine reset(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

!$omp master
      call reset_impl(self, ierr=ierr)
!$omp end master
   end subroutine reset

   subroutine reset_impl(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr
      integer :: i

      if (.not. self%initialized) then
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer reset before init")
         return
      end if

      if (has_active_timers(self)) then
         call report_status(ierr, FTIMER_ERR_ACTIVE, "ftimer reset with active timers; state unchanged")
         return
      end if

      do i = 1, self%num_segments
         if (allocated(self%segments(i)%time)) self%segments(i)%time = 0.0_wp
         if (allocated(self%segments(i)%start_time)) self%segments(i)%start_time = 0.0_wp
         if (allocated(self%segments(i)%is_running)) self%segments(i)%is_running = .false.
         if (allocated(self%segments(i)%call_count)) self%segments(i)%call_count = 0
      end do
      if (allocated(self%call_stack%ids)) deallocate (self%call_stack%ids)
      self%call_stack%depth = 0
      self%init_wtime = self%wtime()
      self%init_date = ftimer_date_string()

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine reset_impl

   subroutine repair_mismatch(self, idx)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: idx
      integer, allocatable :: unwound_ids(:)
      integer :: top_id
      integer :: restart_ctx
      integer :: unwind_count
      integer :: i
      real(wp) :: now

      if (.not. stack_contains(self%call_stack, idx)) return

      now = self%wtime()
      allocate (unwound_ids(self%call_stack%depth))
      unwind_count = 0

      do while ((self%call_stack%depth > 0) .and. (self%call_stack%top() /= idx))
         top_id = self%call_stack%top()
         call stop_segment_with_now(self, top_id, now, fire_callback=.false.)
         unwind_count = unwind_count + 1
         unwound_ids(unwind_count) = top_id
      end do

      if ((self%call_stack%depth > 0) .and. (self%call_stack%top() == idx)) then
         call stop_segment_with_now(self, idx, now, fire_callback=.false.)
      end if

      do i = unwind_count, 1, -1
         restart_ctx = self%segments(unwound_ids(i))%contexts%find(self%call_stack)
         if (restart_ctx <= 0) then
            restart_ctx = self%segments(unwound_ids(i))%contexts%add(self%call_stack)
         end if
         call ensure_context_storage(self%segments(unwound_ids(i)), restart_ctx)
         call self%call_stack%push(unwound_ids(i))
         self%segments(unwound_ids(i))%start_time(restart_ctx) = now
         self%segments(unwound_ids(i))%is_running(restart_ctx) = .true.
      end do
   end subroutine repair_mismatch

   real(wp) function wtime(self) result(now)
      class(ftimer_t), intent(in) :: self

      if (associated(self%clock)) then
         now = self%clock()
      else
         now = ftimer_default_clock()
      end if
   end function wtime

   integer function find_or_create_segment(self, name) result(idx)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      type(ftimer_segment_t), allocatable :: new_segments(:)

      idx = find_segment_index(self, name)
      if (idx > 0) return

      allocate (new_segments(self%num_segments + 1))
      if (self%num_segments > 0) then
         new_segments(1:self%num_segments) = self%segments(1:self%num_segments)
      end if
      new_segments(self%num_segments + 1)%name = name
      call move_alloc(new_segments, self%segments)

      self%num_segments = self%num_segments + 1
      idx = self%num_segments
   end function find_or_create_segment

#ifdef FTIMER_BUILD_TESTS
   subroutine ftimer_test_get_state(self, state)
      class(ftimer_t), intent(in) :: self
      type(ftimer_test_state_t), intent(out) :: state

      state%call_stack = self%call_stack
      state%num_segments = self%num_segments
      state%init_wtime = self%init_wtime
      state%init_date = self%init_date
      state%initialized = self%initialized
      state%mismatch_mode = self%mismatch_mode
#ifdef FTIMER_USE_MPI
      state%mpi_comm = self%mpi_comm
      state%mpi_rank = self%mpi_rank
      state%mpi_nprocs = self%mpi_nprocs
#endif

      if (allocated(state%segments)) deallocate (state%segments)
      if (allocated(self%segments)) then
         allocate (state%segments(size(self%segments)))
         state%segments = self%segments
      end if
   end subroutine ftimer_test_get_state

#endif

   subroutine clear_runtime_state(self, keep_hooks)
      class(ftimer_t), intent(inout) :: self
      logical, intent(in) :: keep_hooks

      if (allocated(self%segments)) deallocate (self%segments)
      if (allocated(self%call_stack%ids)) deallocate (self%call_stack%ids)
      self%call_stack%depth = 0
      self%num_segments = 0
      self%init_wtime = 0.0_wp
      self%init_date = ''
      self%initialized = .false.
      self%mismatch_mode = FTIMER_MISMATCH_STRICT
#ifdef FTIMER_USE_MPI
      self%mpi_comm = -1
      self%mpi_rank = -1
      self%mpi_nprocs = 1
#endif
      if (.not. keep_hooks) then
         nullify (self%clock)
         nullify (self%on_event)
         self%user_data = c_null_ptr
      end if
   end subroutine clear_runtime_state

   subroutine restore_default_clock(self)
      class(ftimer_t), intent(inout) :: self

#ifdef FTIMER_USE_MPI
      self%clock => ftimer_mpi_clock
#else
      self%clock => ftimer_default_clock
#endif
   end subroutine restore_default_clock

   subroutine ensure_context_storage(segment, required_size)
      type(ftimer_segment_t), intent(inout) :: segment
      integer, intent(in) :: required_size
      integer :: old_size
      integer, allocatable :: new_counts(:)
      logical, allocatable :: new_running(:)
      real(wp), allocatable :: new_start_times(:)
      real(wp), allocatable :: new_times(:)

      old_size = 0
      if (allocated(segment%time)) old_size = size(segment%time)
      if (old_size >= required_size) return

      allocate (new_times(required_size))
      allocate (new_start_times(required_size))
      allocate (new_running(required_size))
      allocate (new_counts(required_size))

      new_times = 0.0_wp
      new_start_times = 0.0_wp
      new_running = .false.
      new_counts = 0

      if (old_size > 0) then
         new_times(1:old_size) = segment%time
         new_start_times(1:old_size) = segment%start_time
         new_running(1:old_size) = segment%is_running
         new_counts(1:old_size) = segment%call_count
      end if

      call move_alloc(new_times, segment%time)
      call move_alloc(new_start_times, segment%start_time)
      call move_alloc(new_running, segment%is_running)
      call move_alloc(new_counts, segment%call_count)
   end subroutine ensure_context_storage

   integer function find_segment_index(self, name) result(idx)
      class(ftimer_t), intent(in) :: self
      character(len=*), intent(in) :: name
      integer :: i

      idx = 0
      do i = 1, self%num_segments
         if (self%segments(i)%name == name) then
            idx = i
            return
         end if
      end do
   end function find_segment_index

   logical function has_active_timers(self) result(has_active)
      class(ftimer_t), intent(in) :: self

      has_active = self%call_stack%depth > 0
   end function has_active_timers

   subroutine normalize_name(name, normalized_name, status, message)
      character(len=*), intent(in) :: name
      character(len=FTIMER_NAME_LEN), intent(out) :: normalized_name
      integer, intent(out) :: status
      character(len=*), intent(out) :: message
      integer :: i
      integer :: code
      integer :: trimmed_len

      normalized_name = ''
      message = ''
      trimmed_len = len_trim(name)

      if (trimmed_len <= 0) then
         status = FTIMER_ERR_INVALID_NAME
         message = "ftimer timer name must not be empty"
         return
      end if

      if (trimmed_len > FTIMER_NAME_LEN) then
         status = FTIMER_ERR_INVALID_NAME
         write (message, '(a,i0)') "ftimer timer name exceeds FTIMER_NAME_LEN=", FTIMER_NAME_LEN
         return
      end if

      if (name(1:1) == ' ') then
         status = FTIMER_ERR_INVALID_NAME
         message = "ftimer timer name must not begin with whitespace"
         return
      end if

      do i = 1, trimmed_len
         code = iachar(name(i:i))
         if ((code < 32) .or. (code == 127)) then
            status = FTIMER_ERR_INVALID_NAME
            write (message, '(a,i0)') "ftimer timer name contains control character at position ", i
            return
         end if
      end do

      normalized_name(1:trimmed_len) = name(1:trimmed_len)
      status = FTIMER_SUCCESS
   end subroutine normalize_name

   subroutine report_status(ierr, code, message)
      integer, intent(out), optional :: ierr
      integer, intent(in) :: code
      character(len=*), intent(in) :: message

      if (present(ierr)) then
         ierr = code
      else
         write (error_unit, '(a)') trim(message)
      end if
   end subroutine report_status

   logical function stack_contains(stack, id) result(found)
      type(ftimer_call_stack_t), intent(in) :: stack
      integer, intent(in) :: id

      found = .false.
      if (stack%depth <= 0) return
      found = any(stack%ids(1:stack%depth) == id)
   end function stack_contains

   subroutine stop_segment_with_now(self, id, now, fire_callback)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: id
      real(wp), intent(in) :: now
      logical, intent(in) :: fire_callback
      integer :: ctx
      integer :: popped_id

      popped_id = self%call_stack%pop()
      if (popped_id /= id) then
         error stop "ftimer internal stop_segment_with_now stack corruption"
      end if

      ctx = self%segments(id)%contexts%find(self%call_stack)
      if (ctx <= 0) then
         error stop "ftimer internal stop_segment_with_now missing context"
      end if

      self%segments(id)%time(ctx) = self%segments(id)%time(ctx) + now - self%segments(id)%start_time(ctx)
      self%segments(id)%is_running(ctx) = .false.

      if (fire_callback .and. associated(self%on_event)) then
         call self%on_event(id, ctx, FTIMER_EVENT_STOP, now, self%user_data)
      end if
   end subroutine stop_segment_with_now

   logical function has_recorded_timing(self) result(has_data)
      class(ftimer_t), intent(in) :: self
      integer :: i

      has_data = .false.
      do i = 1, self%num_segments
         if (allocated(self%segments(i)%call_count)) then
            if (any(self%segments(i)%call_count > 0)) then
               has_data = .true.
               return
            end if
         end if
         if (allocated(self%segments(i)%time)) then
            if (any(self%segments(i)%time /= 0.0_wp)) then
               has_data = .true.
               return
            end if
         end if
         if (allocated(self%segments(i)%is_running)) then
            if (any(self%segments(i)%is_running)) then
               has_data = .true.
               return
            end if
         end if
      end do
   end function has_recorded_timing

   logical function can_configure_clock(self) result(can_configure)
      class(ftimer_t), intent(in) :: self

      can_configure = .false.
      if (has_active_timers(self)) return
      if (self%initialized .and. has_recorded_timing(self)) return
      can_configure = .true.
   end function can_configure_clock

   logical function needs_init_wtime_rebase(self) result(needs_rebase)
      class(ftimer_t), intent(in) :: self

      needs_rebase = .false.
      if (.not. self%initialized) return
      if (.not. associated(self%clock)) return
      if (has_recorded_timing(self)) return
#ifdef FTIMER_USE_MPI
      if (associated(self%clock, ftimer_mpi_clock)) return
#else
      if (associated(self%clock, ftimer_default_clock)) return
#endif
      needs_rebase = .true.
   end function needs_init_wtime_rebase

end module ftimer_core
