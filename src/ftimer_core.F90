module ftimer_core
   use, intrinsic :: iso_c_binding, only: c_null_ptr, c_ptr
   use, intrinsic :: iso_fortran_env, only: error_unit, int64
   use ftimer_clock, only: ftimer_date_string, ftimer_default_clock, ftimer_mpi_clock
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_IO, FTIMER_ERR_INVALID_NAME, FTIMER_ERR_MISMATCH, &
                           FTIMER_ERR_NOT_INIT, FTIMER_ERR_UNKNOWN, FTIMER_EVENT_START, FTIMER_EVENT_STOP, &
                           FTIMER_MISMATCH_REPAIR, FTIMER_MISMATCH_STRICT, FTIMER_MISMATCH_WARN, FTIMER_SUCCESS, &
                           ftimer_call_stack_t, ftimer_clock_func, ftimer_hook_proc, ftimer_metadata_t, &
                           ftimer_mpi_summary_t, ftimer_mpi_union_summary_t, ftimer_segment_t, ftimer_summary_t, wp
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Comm, MPI_COMM_WORLD
#endif
   implicit none
   private

   public :: ftimer_t
   public :: ftimer_oop_guard_t
   public :: ftimer_oop_scope
   public :: ftimer_internal_start_scope_activation
   public :: ftimer_internal_stop_scope_activation
#ifdef FTIMER_BUILD_TESTS
   public :: ftimer_test_get_state
   public :: ftimer_test_set_call_count
   public :: ftimer_test_state_t
#endif

   integer, parameter :: FTIMER_SEGMENT_INITIAL_CAPACITY = 16
   integer, parameter :: FTIMER_CONTEXT_STORAGE_INITIAL_CAPACITY = 4
   integer, parameter :: FTIMER_CONTEXT_INDEX_INITIAL_CAPACITY = 8
   integer, parameter :: FTIMER_NAME_INDEX_INITIAL_CAPACITY = 32
   integer, parameter :: FTIMER_NAME_INDEX_LOAD_NUMERATOR = 7
   integer, parameter :: FTIMER_NAME_INDEX_LOAD_DENOMINATOR = 10
   integer, parameter :: FTIMER_STATUS_MESSAGE_LEN = 2048
   integer(int64), parameter :: FTIMER_NAME_HASH_MODULUS = 2147483629_int64
   integer(int64), parameter :: FTIMER_NAME_HASH_MULTIPLIER = 131_int64
   integer(int64), parameter :: FTIMER_NAME_HASH_MIX_MULTIPLIER = 1597334677_int64

#ifdef FTIMER_BUILD_TESTS
   type :: ftimer_test_state_t
      type(ftimer_call_stack_t) :: call_stack
      type(ftimer_segment_t), allocatable :: segments(:)
      integer, allocatable :: segment_ids(:)
      integer, allocatable :: segment_id_slots(:)
      integer :: num_segments = 0
      integer :: next_segment_id = 1
      real(wp) :: init_wtime = 0.0_wp
      character(len=40) :: init_date = ''
      logical :: initialized = .false.
      integer :: mismatch_mode = FTIMER_MISMATCH_STRICT
#ifdef FTIMER_USE_MPI
      logical :: mpi_comm_was_present = .false.
      integer :: mpi_rank = -1
      integer :: mpi_nprocs = 1
#endif
   end type ftimer_test_state_t
#endif

   type :: ftimer_context_index_t
      integer, allocatable :: slots(:)
   end type ftimer_context_index_t

   ! Keeps integer init options keyword-only so removed legacy MPI communicator
   ! handles cannot be accepted as positional integer arguments.
   type :: ftimer_init_keyword_guard_t
   end type ftimer_init_keyword_guard_t

   type :: ftimer_t
      private
      type(ftimer_call_stack_t) :: call_stack
      type(ftimer_segment_t), allocatable :: segments(:)
      integer, allocatable :: segment_name_slots(:)
      integer, allocatable :: segment_ids(:)
      integer, allocatable :: segment_id_slots(:)
      type(ftimer_context_index_t), allocatable :: segment_context_indices(:)
      integer :: num_segments = 0
      integer :: next_segment_id = 1
      integer(int64) :: next_activation_token = 0_int64
      real(wp) :: init_wtime = 0.0_wp
      character(len=40) :: init_date = ''
      logical :: initialized = .false.
      integer :: mismatch_mode = FTIMER_MISMATCH_STRICT
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: mpi_comm
      logical :: mpi_comm_was_present = .false.
      integer :: mpi_rank = -1
      integer :: mpi_nprocs = 1
#endif
      procedure(ftimer_clock_func), pointer, nopass :: clock => null()
      procedure(ftimer_hook_proc), pointer, nopass :: on_event => null()
      type(c_ptr) :: user_data = c_null_ptr
   contains
      procedure, private :: init_without_comm
#ifdef FTIMER_USE_MPI
      procedure, private :: init_with_mpi_comm
      generic, public :: init => init_without_comm, init_with_mpi_comm
#else
      procedure, public :: init => init_without_comm
#endif
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
      procedure :: mpi_union_summary
      procedure :: print_summary
      procedure :: write_summary
      procedure :: write_summary_csv
      procedure :: print_mpi_summary
      procedure :: write_mpi_summary
      procedure :: write_mpi_summary_csv
      procedure :: print_mpi_union_summary
      procedure :: write_mpi_union_summary
      procedure :: write_mpi_union_summary_csv
      procedure, private :: wtime
      procedure, private :: find_or_create_segment
      procedure, private :: repair_mismatch
   end type ftimer_t

   type :: ftimer_oop_guard_t
      private
      type(ftimer_t), pointer :: timer => null()
      integer :: timer_id = 0
      integer(int64) :: activation_token = 0_int64
      logical :: active = .false.
   contains
      procedure, public :: stop => ftimer_oop_guard_stop
      final :: ftimer_oop_guard_finalize
      procedure, private :: assign => ftimer_oop_guard_assign
      generic, public :: assignment(=) => assign
   end type ftimer_oop_guard_t

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

      module subroutine mpi_union_summary(self, summary, ierr)
         class(ftimer_t), intent(in) :: self
         type(ftimer_mpi_union_summary_t), intent(out) :: summary
         integer, intent(out), optional :: ierr
      end subroutine mpi_union_summary

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

      module subroutine write_summary_csv(self, filename, append, metadata, ierr)
         class(ftimer_t), intent(in) :: self
         character(len=*), intent(in) :: filename
         logical, intent(in), optional :: append
         type(ftimer_metadata_t), intent(in), optional :: metadata(:)
         integer, intent(out), optional :: ierr
      end subroutine write_summary_csv

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

      module subroutine write_mpi_summary_csv(self, filename, append, metadata, ierr)
         class(ftimer_t), intent(in) :: self
         character(len=*), intent(in) :: filename
         logical, intent(in), optional :: append
         type(ftimer_metadata_t), intent(in), optional :: metadata(:)
         integer, intent(out), optional :: ierr
      end subroutine write_mpi_summary_csv

      module subroutine print_mpi_union_summary(self, unit, metadata, ierr)
         class(ftimer_t), intent(in) :: self
         integer, intent(in), optional :: unit
         type(ftimer_metadata_t), intent(in), optional :: metadata(:)
         integer, intent(out), optional :: ierr
      end subroutine print_mpi_union_summary

      module subroutine write_mpi_union_summary(self, filename, append, metadata, ierr)
         class(ftimer_t), intent(in) :: self
         character(len=*), intent(in) :: filename
         logical, intent(in), optional :: append
         type(ftimer_metadata_t), intent(in), optional :: metadata(:)
         integer, intent(out), optional :: ierr
      end subroutine write_mpi_union_summary

      module subroutine write_mpi_union_summary_csv(self, filename, append, metadata, ierr)
         class(ftimer_t), intent(in) :: self
         character(len=*), intent(in) :: filename
         logical, intent(in), optional :: append
         type(ftimer_metadata_t), intent(in), optional :: metadata(:)
         integer, intent(out), optional :: ierr
      end subroutine write_mpi_union_summary_csv
   end interface

contains

   subroutine ftimer_oop_scope(timer, guard, name, ierr)
      type(ftimer_t), pointer, intent(inout) :: timer
      type(ftimer_oop_guard_t), intent(inout) :: guard
      character(len=*), intent(in) :: name
      integer, intent(inout), optional :: ierr

#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call ftimer_oop_scope_impl(timer, guard, name, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end subroutine ftimer_oop_scope

   subroutine ftimer_oop_scope_impl(timer, guard, name, ierr)
      type(ftimer_t), pointer, intent(inout) :: timer
      type(ftimer_oop_guard_t), intent(inout) :: guard
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr
      integer :: id
      integer(int64) :: activation_token

      if (guard%active) then
         call report_status(ierr, FTIMER_ERR_ACTIVE, "ftimer OOP scope called with an active guard; state unchanged")
         return
      end if

      call clear_oop_guard(guard)

      if (.not. associated(timer)) then
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer OOP scope with unassociated timer pointer")
         return
      end if

      call start_scope_activation_impl(timer, name, id, activation_token, ierr=ierr)
      if ((id <= 0) .or. (activation_token == 0_int64)) return

      guard%timer => timer
      guard%timer_id = id
      guard%activation_token = activation_token
      guard%active = .true.
   end subroutine ftimer_oop_scope_impl

   subroutine ftimer_oop_guard_stop(self, ierr)
      class(ftimer_oop_guard_t), intent(inout) :: self
      integer, intent(inout), optional :: ierr
      integer :: status

      if (.not. self%active) then
         if (present(ierr)) ierr = FTIMER_SUCCESS
         return
      end if

      if (.not. associated(self%timer)) then
         call clear_oop_guard(self)
         if (present(ierr)) ierr = FTIMER_SUCCESS
         return
      end if

      status = ftimer_internal_stop_scope_activation(self%timer, self%timer_id, self%activation_token, ierr=ierr)
      if (status == FTIMER_SUCCESS) call clear_oop_guard(self)
   end subroutine ftimer_oop_guard_stop

   subroutine ftimer_oop_guard_finalize(self)
      type(ftimer_oop_guard_t), intent(inout) :: self

      call self%stop()
   end subroutine ftimer_oop_guard_finalize

   subroutine ftimer_oop_guard_assign(lhs, rhs)
      class(ftimer_oop_guard_t), intent(inout) :: lhs
      type(ftimer_oop_guard_t), intent(in) :: rhs

      if (lhs%active .or. rhs%active) then
         write (error_unit, '(a)') "ftimer OOP guard assignment is unsupported; active ownership was not copied"
      end if

      if (.not. lhs%active) call clear_oop_guard(lhs)
   end subroutine ftimer_oop_guard_assign

   subroutine clear_oop_guard(guard)
      class(ftimer_oop_guard_t), intent(inout) :: guard

      nullify (guard%timer)
      guard%timer_id = 0
      guard%activation_token = 0_int64
      guard%active = .false.
   end subroutine clear_oop_guard

   subroutine ftimer_internal_start_scope_activation(self, name, id, activation_token, ierr)
      class(ftimer_t), target, intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out) :: id
      integer(int64), intent(out) :: activation_token
      integer, intent(out), optional :: ierr

      id = 0
      activation_token = 0_int64
#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call start_scope_activation_impl(self, name, id, activation_token, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end subroutine ftimer_internal_start_scope_activation

   integer function ftimer_internal_stop_scope_activation(self, id, activation_token, ierr) result(status)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: id
      integer(int64), intent(in) :: activation_token
      integer, intent(inout), optional :: ierr

      status = FTIMER_ERR_ACTIVE
#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      status = stop_scope_activation_impl(self, id, activation_token, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end function ftimer_internal_stop_scope_activation

   subroutine init_without_comm(self, keyword_guard, mismatch_mode, ierr)
      class(ftimer_t), intent(inout) :: self
      type(ftimer_init_keyword_guard_t), intent(in), optional :: keyword_guard
      integer, intent(in), optional :: mismatch_mode
      integer, intent(out), optional :: ierr

      if (present(keyword_guard)) then
         call report_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer init received an invalid positional guard argument")
         return
      end if

#ifdef FTIMER_USE_OPENMP
      !$omp master
#endif
      call init_impl(self, ierr=ierr, mismatch_mode=mismatch_mode)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end subroutine init_without_comm

#ifdef FTIMER_USE_MPI
   subroutine init_with_mpi_comm(self, comm, keyword_guard, mismatch_mode, ierr)
      class(ftimer_t), intent(inout) :: self
      type(MPI_Comm), intent(in) :: comm
      type(ftimer_init_keyword_guard_t), intent(in), optional :: keyword_guard
      integer, intent(in), optional :: mismatch_mode
      integer, intent(out), optional :: ierr

      if (present(keyword_guard)) then
         call report_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer init received an invalid positional guard argument")
         return
      end if

#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call init_impl(self, ierr=ierr, comm=comm, mismatch_mode=mismatch_mode)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end subroutine init_with_mpi_comm
#endif

   subroutine init_impl(self, mismatch_mode, ierr, comm)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in), optional :: mismatch_mode
      integer, intent(out), optional :: ierr
#ifdef FTIMER_USE_MPI
      type(MPI_Comm), intent(in), optional :: comm
      type(MPI_Comm) :: requested_mpi_comm
      logical :: requested_mpi_comm_was_present
#else
      integer, intent(in), optional :: comm
#endif

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

#ifdef FTIMER_USE_MPI
      requested_mpi_comm = MPI_COMM_WORLD
      requested_mpi_comm_was_present = .false.
      if (present(comm)) then
         requested_mpi_comm = comm
         requested_mpi_comm_was_present = .true.
      end if
#endif

      call clear_runtime_state(self, keep_hooks=.true.)
      self%initialized = .true.

      if (present(mismatch_mode)) then
         self%mismatch_mode = mismatch_mode
      else
         self%mismatch_mode = FTIMER_MISMATCH_STRICT
      end if

#ifdef FTIMER_USE_MPI
      self%mpi_comm = requested_mpi_comm
      self%mpi_comm_was_present = requested_mpi_comm_was_present
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

#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call finalize_impl(self, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end subroutine finalize

   subroutine finalize_impl(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

      if (.not. self%initialized) then
         call clear_callback_state(self)
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

#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call set_clock_impl(self, clock, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
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
      if (self%initialized) call rebase_summary_window(self)
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine set_clock_impl

   subroutine clear_clock(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call clear_clock_impl(self, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end subroutine clear_clock

   subroutine clear_clock_impl(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

      if (.not. can_configure_clock(self)) then
         call report_status(ierr, FTIMER_ERR_ACTIVE, "ftimer clear_clock after timing has started; state unchanged")
         return
      end if

      call restore_default_clock(self)
      if (self%initialized) call rebase_summary_window(self)
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine clear_clock_impl

   subroutine set_callback(self, on_event, user_data, ierr)
      class(ftimer_t), intent(inout) :: self
      procedure(ftimer_hook_proc) :: on_event
      type(c_ptr), intent(in), optional :: user_data
      integer, intent(out), optional :: ierr

#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call set_callback_impl(self, on_event, user_data=user_data, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
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

#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call clear_callback_impl(self, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end subroutine clear_callback

   subroutine clear_callback_impl(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

      if (has_active_timers(self)) then
         call report_status(ierr, FTIMER_ERR_ACTIVE, "ftimer clear_callback with active timers; state unchanged")
         return
      end if

      call clear_callback_state(self)
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine clear_callback_impl

   subroutine start(self, name, ierr)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call start_impl(self, name, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end subroutine start

   subroutine start_impl(self, name, ierr, activation_token)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr
      integer(int64), intent(out), optional :: activation_token
      integer :: segment_idx
      integer :: status
      integer :: trimmed_len
      character(len=FTIMER_STATUS_MESSAGE_LEN) :: message

      call start_trace_mark("start_impl: enter")
      if (present(activation_token)) activation_token = 0_int64

      if (.not. self%initialized) then
         call start_trace_mark("start_impl: not initialized")
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer start before init")
         return
      end if

      call normalize_name(name, trimmed_len, status, message)
      call start_trace_mark("start_impl: after normalize_name")
      if (status /= FTIMER_SUCCESS) then
         call report_status(ierr, status, trim(message))
         return
      end if

      call start_trace_mark("start_impl: before find_or_create_segment")
      segment_idx = self%find_or_create_segment(name(1:trimmed_len))
      call start_trace_mark("start_impl: after find_or_create_segment")
      call start_trace_mark("start_impl: before start_segment_impl")
      call start_segment_impl(self, segment_idx, ierr=ierr, activation_token=activation_token)
      call start_trace_mark("start_impl: after start_segment_impl")
   end subroutine start_impl

   subroutine stop(self, name, ierr)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call stop_impl(self, name, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end subroutine stop

   subroutine stop_impl(self, name, ierr)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr
      integer :: segment_idx
      integer :: status
      integer :: trimmed_len
      character(len=FTIMER_STATUS_MESSAGE_LEN) :: message

      if (.not. self%initialized) then
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer stop before init")
         return
      end if

      call normalize_name(name, trimmed_len, status, message)
      if (status /= FTIMER_SUCCESS) then
         call report_status(ierr, status, trim(message))
         return
      end if

      segment_idx = find_segment_index(self, name(1:trimmed_len))
      if (segment_idx <= 0) then
         message = "ftimer stop on unknown timer: "//name(1:trimmed_len)
         call report_status(ierr, FTIMER_ERR_UNKNOWN, trim(message))
         return
      end if

      call stop_segment_impl(self, segment_idx, ierr=ierr)
   end subroutine stop_impl

   subroutine start_id(self, id, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr

#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call start_id_impl(self, id, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end subroutine start_id

   subroutine start_id_impl(self, id, ierr, activation_token)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr
      integer(int64), intent(out), optional :: activation_token
      integer :: segment_idx

      if (present(activation_token)) activation_token = 0_int64

      if (.not. self%initialized) then
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer start_id before init")
         return
      end if

      segment_idx = find_segment_id_index(self, id)
      if (segment_idx <= 0) then
         call report_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer start_id with unknown timer id")
         return
      end if

      call start_segment_impl(self, segment_idx, ierr=ierr, activation_token=activation_token)
   end subroutine start_id_impl

   subroutine start_segment_impl(self, segment_idx, ierr, activation_token)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: segment_idx
      integer, intent(out), optional :: ierr
      integer(int64), intent(out), optional :: activation_token
      integer :: ctx
      integer(int64) :: token
      real(wp) :: now

      call start_trace_mark("start_segment_impl: enter")
      if (present(activation_token)) activation_token = 0_int64

      call start_trace_mark("start_segment_impl: before find_or_create_segment_context")
      ctx = find_or_create_segment_context(self, segment_idx)
      call start_trace_mark("start_segment_impl: after find_or_create_segment_context")
      call start_trace_mark("start_segment_impl: before ensure_context_storage")
      call ensure_context_storage(self%segments(segment_idx), ctx)
      call start_trace_mark("start_segment_impl: after ensure_context_storage")

      if (self%segments(segment_idx)%call_count(ctx) >= huge(0_int64)) then
         call report_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer start call count overflow")
         return
      end if

      call start_trace_mark("start_segment_impl: before create_activation_token")
      token = create_activation_token(self)
      call start_trace_mark("start_segment_impl: after create_activation_token")
      call start_trace_mark("start_segment_impl: before call_stack push")
      call self%call_stack%push(segment_idx, token)
      call start_trace_mark("start_segment_impl: after call_stack push")
      now = self%wtime()
      call start_trace_mark("start_segment_impl: after wtime")
      self%segments(segment_idx)%start_time(ctx) = now
      self%segments(segment_idx)%call_count(ctx) = self%segments(segment_idx)%call_count(ctx) + 1_int64
      self%segments(segment_idx)%is_running(ctx) = .true.
      call start_trace_mark("start_segment_impl: after state updates")

      if (associated(self%on_event)) then
         call self%on_event(public_segment_id(self, segment_idx), ctx, FTIMER_EVENT_START, now, self%user_data)
      end if
      call start_trace_mark("start_segment_impl: after callback check")

      if (present(activation_token)) activation_token = token
      if (present(ierr)) ierr = FTIMER_SUCCESS
      call start_trace_mark("start_segment_impl: exit")
   end subroutine start_segment_impl

   subroutine stop_id(self, id, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr

#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call stop_id_impl(self, id, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end subroutine stop_id

   subroutine stop_id_impl(self, id, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr
      integer :: segment_idx

      if (.not. self%initialized) then
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer stop_id before init")
         return
      end if

      segment_idx = find_segment_id_index(self, id)
      if (segment_idx <= 0) then
         call report_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer stop_id with unknown timer id")
         return
      end if

      call stop_segment_impl(self, segment_idx, ierr=ierr)
   end subroutine stop_id_impl

   subroutine stop_segment_impl(self, segment_idx, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: segment_idx
      integer, intent(out), optional :: ierr
      character(len=FTIMER_STATUS_MESSAGE_LEN) :: message

      if (self%call_stack%depth <= 0) then
         call report_status(ierr, FTIMER_ERR_MISMATCH, "ftimer stop mismatch on empty call stack")
         return
      end if

      if (self%call_stack%top() == segment_idx) then
         call stop_segment_with_now(self, segment_idx, self%wtime(), fire_callback=.true.)
         if (present(ierr)) ierr = FTIMER_SUCCESS
         return
      end if

      message = "ftimer stop mismatch: requested "//trim(self%segments(segment_idx)%name)// &
                " but top of stack is "//trim(self%segments(self%call_stack%top())%name)

      select case (self%mismatch_mode)
      case (FTIMER_MISMATCH_STRICT)
         call report_status(ierr, FTIMER_ERR_MISMATCH, trim(message))
         return
      case (FTIMER_MISMATCH_WARN)
         if (.not. stack_contains(self%call_stack, segment_idx)) then
            call report_status(ierr, FTIMER_ERR_MISMATCH, trim(message))
            return
         end if

         call report_status(ierr, FTIMER_ERR_MISMATCH, trim(message))
         call self%repair_mismatch(segment_idx)
      case (FTIMER_MISMATCH_REPAIR)
         if (.not. stack_contains(self%call_stack, segment_idx)) then
            call report_status(ierr, FTIMER_ERR_MISMATCH, trim(message))
            return
         end if

         call self%repair_mismatch(segment_idx)
         if (present(ierr)) ierr = FTIMER_SUCCESS
      case default
         call report_status(ierr, FTIMER_ERR_MISMATCH, trim(message))
         return
      end select
   end subroutine stop_segment_impl

   integer function lookup(self, name, ierr) result(id)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      id = 0
#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      id = lookup_impl(self, name, ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
   end function lookup

   integer function lookup_impl(self, name, ierr) result(id)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr
      integer :: status
      integer :: trimmed_len
      character(len=FTIMER_STATUS_MESSAGE_LEN) :: message

      id = 0
      if (.not. self%initialized) then
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer lookup before init")
         return
      end if

      call normalize_name(name, trimmed_len, status, message)
      if (status /= FTIMER_SUCCESS) then
         call report_status(ierr, status, trim(message))
         return
      end if

      id = public_segment_id(self, self%find_or_create_segment(name(1:trimmed_len)))
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end function lookup_impl

   subroutine reset(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

#ifdef FTIMER_USE_OPENMP
!$omp master
#endif
      call reset_impl(self, ierr=ierr)
#ifdef FTIMER_USE_OPENMP
!$omp end master
#endif
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
         if (allocated(self%segments(i)%call_count)) self%segments(i)%call_count = 0_int64
      end do
      if (allocated(self%call_stack%ids)) deallocate (self%call_stack%ids)
      if (allocated(self%call_stack%activation_tokens)) deallocate (self%call_stack%activation_tokens)
      self%call_stack%depth = 0
      call allocate_empty_call_stack(self%call_stack)
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
      integer(int64) :: restart_token
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
         restart_ctx = find_or_create_segment_context(self, unwound_ids(i))
         call ensure_context_storage(self%segments(unwound_ids(i)), restart_ctx)
         restart_token = create_activation_token(self)
         call self%call_stack%push(unwound_ids(i), restart_token)
         self%segments(unwound_ids(i))%start_time(restart_ctx) = now
         self%segments(unwound_ids(i))%is_running(restart_ctx) = .true.
      end do
   end subroutine repair_mismatch

   subroutine start_scope_activation_impl(self, name, id, activation_token, ierr)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out) :: id
      integer(int64), intent(out) :: activation_token
      integer, intent(out), optional :: ierr

      id = 0
      activation_token = 0_int64

      call start_impl(self, name, ierr=ierr, activation_token=activation_token)
      if (activation_token == 0_int64) return

      if (self%call_stack%depth > 0) then
         id = self%call_stack%top()
      end if
   end subroutine start_scope_activation_impl

   integer function stop_scope_activation_impl(self, id, activation_token, ierr) result(status)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: id
      integer(int64), intent(in) :: activation_token
      integer, intent(out), optional :: ierr
      character(len=FTIMER_STATUS_MESSAGE_LEN) :: message
      integer :: top_id

      if (.not. self%initialized) then
         status = FTIMER_ERR_NOT_INIT
         call report_status(ierr, status, "ftimer scoped guard stop before init")
         return
      end if

      if ((id < 1) .or. (id > self%num_segments)) then
         status = FTIMER_ERR_UNKNOWN
         call report_status(ierr, status, "ftimer scoped guard stop with unknown timer id")
         return
      end if

      if (self%call_stack%depth <= 0) then
         status = FTIMER_ERR_MISMATCH
         call report_status(ierr, status, "ftimer scoped guard stop mismatch on empty call stack")
         return
      end if

      top_id = self%call_stack%top()
      if (top_id /= id) then
         message = "ftimer scoped guard stop mismatch: owned "//trim(self%segments(id)%name)// &
                   " but top of stack is "//trim(self%segments(top_id)%name)
         status = FTIMER_ERR_MISMATCH
         call report_status(ierr, status, trim(message))
         return
      end if

      if (self%call_stack%top_token() /= activation_token) then
         message = "ftimer scoped guard stop mismatch: activation no longer matches timer "// &
                   trim(self%segments(id)%name)
         status = FTIMER_ERR_MISMATCH
         call report_status(ierr, status, trim(message))
         return
      end if

      call stop_segment_with_now(self, id, self%wtime(), fire_callback=.true.)
      status = FTIMER_SUCCESS
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end function stop_scope_activation_impl

   real(wp) function wtime(self) result(now)
      class(ftimer_t), intent(in) :: self

      if (associated(self%clock)) then
         now = self%clock()
      else
         now = ftimer_default_clock()
      end if
   end function wtime

   integer(int64) function create_activation_token(self) result(activation_token)
      class(ftimer_t), intent(inout) :: self

      if (self%next_activation_token >= huge(self%next_activation_token)) then
         self%next_activation_token = 0_int64
      end if

      self%next_activation_token = self%next_activation_token + 1_int64
      activation_token = self%next_activation_token
   end function create_activation_token

   integer function allocate_segment_id(self) result(id)
      class(ftimer_t), intent(inout) :: self

      if (self%next_segment_id <= 0) error stop "ftimer timer id space exhausted"

      id = self%next_segment_id
      if (self%next_segment_id >= huge(self%next_segment_id)) then
         self%next_segment_id = -1
      else
         self%next_segment_id = self%next_segment_id + 1
      end if
   end function allocate_segment_id

   integer function find_or_create_segment(self, name) result(idx)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer :: new_idx

      call start_trace_mark("find_or_create_segment: enter")
      idx = find_segment_index(self, name)
      call start_trace_mark("find_or_create_segment: after find_segment_index")
      if (idx > 0) return

      new_idx = self%num_segments + 1
      call start_trace_mark("find_or_create_segment: before ensure_segment_capacity")
      call ensure_segment_capacity(self, new_idx)
      call start_trace_mark("find_or_create_segment: after ensure_segment_capacity")
      call start_trace_mark("find_or_create_segment: before assign name")
      call assign_allocatable_string(self%segments(new_idx)%name, name)
      call start_trace_mark("find_or_create_segment: after assign name")
      self%segment_ids(new_idx) = allocate_segment_id(self)
      call start_trace_mark("find_or_create_segment: after allocate_segment_id")
      call ensure_segment_name_index(self, new_idx)
      call start_trace_mark("find_or_create_segment: after ensure_segment_name_index")
      call ensure_segment_id_index(self, new_idx)
      call start_trace_mark("find_or_create_segment: after ensure_segment_id_index")

      self%num_segments = new_idx
      call start_trace_mark("find_or_create_segment: before insert_segment_name_slot")
      call insert_segment_name_slot(self%segment_name_slots, name, new_idx)
      call start_trace_mark("find_or_create_segment: after insert_segment_name_slot")
      call insert_segment_id_slot(self%segment_id_slots, self%segment_ids(new_idx), new_idx)
      call start_trace_mark("find_or_create_segment: after insert_segment_id_slot")
      idx = new_idx
      call start_trace_mark("find_or_create_segment: exit")
   end function find_or_create_segment

   subroutine assign_allocatable_string(value, text)
      character(len=:), allocatable, intent(inout) :: value
      character(len=*), intent(in) :: text

      if (allocated(value)) deallocate (value)
      allocate (character(len=len(text)) :: value)
      value = text
   end subroutine assign_allocatable_string

#ifdef FTIMER_BUILD_TESTS
   subroutine ftimer_test_get_state(self, state)
      class(ftimer_t), intent(in) :: self
      type(ftimer_test_state_t), intent(out) :: state

      state%call_stack = self%call_stack
      state%num_segments = self%num_segments
      state%next_segment_id = self%next_segment_id
      state%init_wtime = self%init_wtime
      state%init_date = self%init_date
      state%initialized = self%initialized
      state%mismatch_mode = self%mismatch_mode
#ifdef FTIMER_USE_MPI
      state%mpi_comm_was_present = self%mpi_comm_was_present
      state%mpi_rank = self%mpi_rank
      state%mpi_nprocs = self%mpi_nprocs
#endif

      if (allocated(state%segments)) deallocate (state%segments)
      if (allocated(state%segment_ids)) deallocate (state%segment_ids)
      if (allocated(state%segment_id_slots)) deallocate (state%segment_id_slots)
      if (self%num_segments > 0) then
         allocate (state%segments(self%num_segments))
         state%segments = self%segments(1:self%num_segments)
      end if
      if (allocated(self%segment_ids)) state%segment_ids = self%segment_ids
      if (allocated(self%segment_id_slots)) state%segment_id_slots = self%segment_id_slots
   end subroutine ftimer_test_get_state

   subroutine ftimer_test_set_call_count(self, segment_id, context_id, call_count, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: segment_id
      integer, intent(in) :: context_id
      integer(int64), intent(in) :: call_count
      integer, intent(out), optional :: ierr
      integer :: segment_idx

      if (.not. self%initialized) then
         call report_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer test_set_call_count before init")
         return
      end if

      segment_idx = find_segment_id_index(self, segment_id)
      if (segment_idx <= 0) then
         call report_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer test_set_call_count with unknown segment id")
         return
      end if

      if (.not. allocated(self%segments(segment_idx)%call_count)) then
         call report_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer test_set_call_count before context allocation")
         return
      end if

      if ((context_id < 1) .or. (context_id > self%segments(segment_idx)%contexts%count)) then
         call report_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer test_set_call_count with unknown context id")
         return
      end if

      self%segments(segment_idx)%call_count(context_id) = call_count
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine ftimer_test_set_call_count

#endif

   subroutine clear_runtime_state(self, keep_hooks)
      class(ftimer_t), intent(inout) :: self
      logical, intent(in) :: keep_hooks

      if (allocated(self%segments)) deallocate (self%segments)
      if (allocated(self%segment_name_slots)) deallocate (self%segment_name_slots)
      if (allocated(self%segment_ids)) deallocate (self%segment_ids)
      if (allocated(self%segment_id_slots)) deallocate (self%segment_id_slots)
      if (allocated(self%segment_context_indices)) deallocate (self%segment_context_indices)
      if (allocated(self%call_stack%ids)) deallocate (self%call_stack%ids)
      if (allocated(self%call_stack%activation_tokens)) deallocate (self%call_stack%activation_tokens)
      self%call_stack%depth = 0
      call allocate_empty_call_stack(self%call_stack)
      self%num_segments = 0
      self%init_wtime = 0.0_wp
      self%init_date = ''
      self%initialized = .false.
      self%mismatch_mode = FTIMER_MISMATCH_STRICT
#ifdef FTIMER_USE_MPI
      self%mpi_comm = MPI_COMM_WORLD
      self%mpi_comm_was_present = .false.
      self%mpi_rank = -1
      self%mpi_nprocs = 1
#endif
      if (.not. keep_hooks) then
         nullify (self%clock)
         call clear_callback_state(self)
      end if
   end subroutine clear_runtime_state

   subroutine allocate_empty_call_stack(stack)
      type(ftimer_call_stack_t), intent(inout) :: stack

      stack%depth = 0
      if (.not. allocated(stack%ids)) allocate (stack%ids(1))
      if (.not. allocated(stack%activation_tokens)) allocate (stack%activation_tokens(1))
   end subroutine allocate_empty_call_stack

   subroutine restore_default_clock(self)
      class(ftimer_t), intent(inout) :: self

#ifdef FTIMER_USE_MPI
      self%clock => ftimer_mpi_clock
#else
      self%clock => ftimer_default_clock
#endif
   end subroutine restore_default_clock

   subroutine rebase_summary_window(self)
      class(ftimer_t), intent(inout) :: self

      self%init_wtime = self%wtime()
      self%init_date = ftimer_date_string()
   end subroutine rebase_summary_window

   subroutine clear_callback_state(self)
      class(ftimer_t), intent(inout) :: self

      nullify (self%on_event)
      self%user_data = c_null_ptr
   end subroutine clear_callback_state

   subroutine grow_segment_context_stacks(self, segment_id)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: segment_id
      type(ftimer_call_stack_t), allocatable :: new_stacks(:)
      integer :: new_capacity

      new_capacity = max(FTIMER_CONTEXT_STORAGE_INITIAL_CAPACITY, &
                         2*size(self%segments(segment_id)%contexts%stacks))
      allocate (new_stacks(new_capacity))
      if (self%segments(segment_id)%contexts%count > 0) then
         new_stacks(1:self%segments(segment_id)%contexts%count) = &
            self%segments(segment_id)%contexts%stacks(1:self%segments(segment_id)%contexts%count)
      end if
      call move_alloc(new_stacks, self%segments(segment_id)%contexts%stacks)
   end subroutine grow_segment_context_stacks

   subroutine ensure_context_storage(segment, required_size)
      type(ftimer_segment_t), intent(inout) :: segment
      integer, intent(in) :: required_size
      integer :: new_size
      integer :: old_size
      integer(int64), allocatable :: new_counts(:)
      logical, allocatable :: new_running(:)
      real(wp), allocatable :: new_start_times(:)
      real(wp), allocatable :: new_times(:)

      old_size = 0
      if (allocated(segment%time)) old_size = size(segment%time)
      if (old_size >= required_size) return

      new_size = max(required_size, FTIMER_CONTEXT_STORAGE_INITIAL_CAPACITY)
      if (old_size > 0) then
         do while (new_size < required_size)
            new_size = 2*new_size
         end do
         new_size = max(new_size, 2*old_size)
      end if

      allocate (new_times(new_size))
      allocate (new_start_times(new_size))
      allocate (new_running(new_size))
      allocate (new_counts(new_size))

      new_times = 0.0_wp
      new_start_times = 0.0_wp
      new_running = .false.
      new_counts = 0_int64

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

   subroutine ensure_segment_capacity(self, required_size)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: required_size
      type(ftimer_context_index_t), allocatable :: new_context_indices(:)
      integer, allocatable :: new_ids(:)
      type(ftimer_segment_t), allocatable :: new_segments(:)
      integer :: new_capacity
      integer :: old_capacity

      old_capacity = 0
      if (allocated(self%segments)) old_capacity = size(self%segments)
      if (old_capacity >= required_size) return

      new_capacity = max(required_size, FTIMER_SEGMENT_INITIAL_CAPACITY)
      if (old_capacity > 0) then
         do while (new_capacity < required_size)
            new_capacity = 2*new_capacity
         end do
         new_capacity = max(new_capacity, 2*old_capacity)
      end if

      allocate (new_segments(new_capacity))
      allocate (new_ids(new_capacity))
      allocate (new_context_indices(new_capacity))
      new_ids = 0
      if (self%num_segments > 0) then
         new_segments(1:self%num_segments) = self%segments(1:self%num_segments)
         if (allocated(self%segment_ids)) then
            new_ids(1:self%num_segments) = self%segment_ids(1:self%num_segments)
         end if
         if (allocated(self%segment_context_indices)) then
            new_context_indices(1:self%num_segments) = self%segment_context_indices(1:self%num_segments)
         end if
      end if
      call move_alloc(new_segments, self%segments)
      call move_alloc(new_ids, self%segment_ids)
      call move_alloc(new_context_indices, self%segment_context_indices)
   end subroutine ensure_segment_capacity

   subroutine ensure_segment_name_index(self, required_count)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: required_count
      integer, allocatable :: new_slots(:)
      integer :: current_capacity
      integer :: i
      integer :: new_capacity

      if (required_count <= 0) return

      current_capacity = 0
      if (allocated(self%segment_name_slots)) current_capacity = size(self%segment_name_slots)

      if (current_capacity > 0) then
         if (required_count*FTIMER_NAME_INDEX_LOAD_DENOMINATOR <= &
             FTIMER_NAME_INDEX_LOAD_NUMERATOR*current_capacity) then
            return
         end if
         new_capacity = current_capacity
      else
         new_capacity = FTIMER_NAME_INDEX_INITIAL_CAPACITY
      end if

      do while (required_count*FTIMER_NAME_INDEX_LOAD_DENOMINATOR > &
                FTIMER_NAME_INDEX_LOAD_NUMERATOR*new_capacity)
         new_capacity = 2*new_capacity
      end do

      allocate (new_slots(new_capacity))
      new_slots = 0
      do i = 1, self%num_segments
         call insert_segment_name_slot(new_slots, self%segments(i)%name, i)
      end do

      call move_alloc(new_slots, self%segment_name_slots)
   end subroutine ensure_segment_name_index

   subroutine ensure_segment_id_index(self, required_count)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: required_count
      integer, allocatable :: new_slots(:)
      integer :: current_capacity
      integer :: i
      integer :: new_capacity

      if (required_count <= 0) return

      current_capacity = 0
      if (allocated(self%segment_id_slots)) current_capacity = size(self%segment_id_slots)

      if (current_capacity > 0) then
         if (required_count*FTIMER_NAME_INDEX_LOAD_DENOMINATOR <= &
             FTIMER_NAME_INDEX_LOAD_NUMERATOR*current_capacity) then
            return
         end if
         new_capacity = current_capacity
      else
         new_capacity = FTIMER_NAME_INDEX_INITIAL_CAPACITY
      end if

      do while (required_count*FTIMER_NAME_INDEX_LOAD_DENOMINATOR > &
                FTIMER_NAME_INDEX_LOAD_NUMERATOR*new_capacity)
         new_capacity = 2*new_capacity
      end do

      allocate (new_slots(new_capacity))
      new_slots = 0
      do i = 1, self%num_segments
         call insert_segment_id_slot(new_slots, self%segment_ids(i), i)
      end do

      call move_alloc(new_slots, self%segment_id_slots)
   end subroutine ensure_segment_id_index

   subroutine ensure_segment_context_index(self, segment_id, required_count)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: segment_id
      integer, intent(in) :: required_count
      integer, allocatable :: new_slots(:)
      integer :: current_capacity
      integer :: i
      integer :: new_capacity

      if (required_count <= 0) return
      if (.not. allocated(self%segment_context_indices)) return
      if ((segment_id < 1) .or. (segment_id > size(self%segment_context_indices))) return

      current_capacity = 0
      if (allocated(self%segment_context_indices(segment_id)%slots)) then
         current_capacity = size(self%segment_context_indices(segment_id)%slots)
      end if

      if (current_capacity > 0) then
         if (required_count*FTIMER_NAME_INDEX_LOAD_DENOMINATOR <= &
             FTIMER_NAME_INDEX_LOAD_NUMERATOR*current_capacity) then
            return
         end if
         new_capacity = current_capacity
      else
         new_capacity = FTIMER_CONTEXT_INDEX_INITIAL_CAPACITY
      end if

      do while (required_count*FTIMER_NAME_INDEX_LOAD_DENOMINATOR > &
                FTIMER_NAME_INDEX_LOAD_NUMERATOR*new_capacity)
         new_capacity = 2*new_capacity
      end do

      allocate (new_slots(new_capacity))
      new_slots = 0
      do i = 1, self%segments(segment_id)%contexts%count
         call insert_segment_context_slot(self%segments(segment_id), new_slots, &
                                          self%segments(segment_id)%contexts%stacks(i), i)
      end do

      call move_alloc(new_slots, self%segment_context_indices(segment_id)%slots)
   end subroutine ensure_segment_context_index

   subroutine insert_segment_name_slot(slots, name, id)
      integer, intent(inout) :: slots(:)
      character(len=*), intent(in) :: name
      integer, intent(in) :: id
      integer :: slot
      integer :: start_slot

      if (size(slots) <= 0) error stop "ftimer internal name index has zero capacity"

      slot = hash_name_slot(name, size(slots))
      start_slot = slot
      do
         if (slots(slot) == 0) then
            slots(slot) = id
            return
         end if

         slot = slot + 1
         if (slot > size(slots)) slot = 1
         if (slot == start_slot) exit
      end do

      error stop "ftimer internal name index overflow"
   end subroutine insert_segment_name_slot

   subroutine insert_segment_id_slot(slots, id, segment_idx)
      integer, intent(inout) :: slots(:)
      integer, intent(in) :: id
      integer, intent(in) :: segment_idx
      integer :: candidate_idx
      integer :: slot
      integer :: start_slot

      if (size(slots) <= 0) error stop "ftimer internal id index has zero capacity"

      slot = hash_id_slot(id, size(slots))
      start_slot = slot
      do
         candidate_idx = slots(slot)
         if (candidate_idx == 0) then
            slots(slot) = segment_idx
            return
         end if

         if (candidate_idx == segment_idx) return

         slot = slot + 1
         if (slot > size(slots)) slot = 1
         if (slot == start_slot) exit
      end do

      error stop "ftimer internal id index overflow"
   end subroutine insert_segment_id_slot

   subroutine insert_segment_context_slot(segment, slots, stack, ctx)
      type(ftimer_segment_t), intent(in) :: segment
      integer, intent(inout) :: slots(:)
      type(ftimer_call_stack_t), intent(in) :: stack
      integer, intent(in) :: ctx
      integer :: candidate_ctx
      integer :: slot
      integer :: start_slot

      if (size(slots) <= 0) error stop "ftimer internal context index has zero capacity"

      slot = hash_context_slot(stack, size(slots))
      start_slot = slot
      do
         candidate_ctx = slots(slot)
         if (candidate_ctx == 0) then
            slots(slot) = ctx
            return
         end if

         if (candidate_ctx == ctx) return
         if ((candidate_ctx >= 1) .and. (candidate_ctx <= segment%contexts%count)) then
            if (segment%contexts%stacks(candidate_ctx)%equals(stack)) return
         end if

         slot = slot + 1
         if (slot > size(slots)) slot = 1
         if (slot == start_slot) exit
      end do

      error stop "ftimer internal context index overflow"
   end subroutine insert_segment_context_slot

   integer function find_segment_index(self, name) result(idx)
      class(ftimer_t), intent(in) :: self
      character(len=*), intent(in) :: name
      integer :: candidate_id
      integer :: i
      integer :: slot
      integer :: start_slot

      idx = 0
      if (self%num_segments <= 0) return

      if (allocated(self%segment_name_slots)) then
         slot = hash_name_slot(name, size(self%segment_name_slots))
         start_slot = slot
         do
            candidate_id = self%segment_name_slots(slot)
            if (candidate_id == 0) return
            if ((candidate_id >= 1) .and. (candidate_id <= self%num_segments)) then
               if (self%segments(candidate_id)%name == name) then
                  idx = candidate_id
                  return
               end if
            end if

            slot = slot + 1
            if (slot > size(self%segment_name_slots)) slot = 1
            if (slot == start_slot) return
         end do
      end if

      do i = 1, self%num_segments
         if (self%segments(i)%name == name) then
            idx = i
            return
         end if
      end do
   end function find_segment_index

   integer function public_segment_id(self, segment_idx) result(id)
      class(ftimer_t), intent(in) :: self
      integer, intent(in) :: segment_idx

      id = 0
      if ((segment_idx < 1) .or. (segment_idx > self%num_segments)) return
      if (allocated(self%segment_ids)) then
         if (segment_idx <= size(self%segment_ids)) then
            id = self%segment_ids(segment_idx)
            if (id > 0) return
         end if
      end if

      id = segment_idx
   end function public_segment_id

   integer function find_segment_id_index(self, id) result(idx)
      class(ftimer_t), intent(in) :: self
      integer, intent(in) :: id
      integer :: candidate_idx
      integer :: i
      integer :: slot
      integer :: start_slot

      idx = 0
      if ((id <= 0) .or. (self%num_segments <= 0)) return

      if (allocated(self%segment_id_slots) .and. allocated(self%segment_ids)) then
         slot = hash_id_slot(id, size(self%segment_id_slots))
         start_slot = slot
         do
            candidate_idx = self%segment_id_slots(slot)
            if (candidate_idx == 0) return
            if ((candidate_idx >= 1) .and. (candidate_idx <= self%num_segments)) then
               if (self%segment_ids(candidate_idx) == id) then
                  idx = candidate_idx
                  return
               end if
            end if

            slot = slot + 1
            if (slot > size(self%segment_id_slots)) slot = 1
            if (slot == start_slot) return
         end do
      end if

      if (allocated(self%segment_ids)) then
         do i = 1, self%num_segments
            if (self%segment_ids(i) == id) then
               idx = i
               return
            end if
         end do
      end if
   end function find_segment_id_index

   integer function find_segment_context(self, segment_id) result(ctx)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: segment_id
      integer :: candidate_ctx
      integer :: slot
      integer :: start_slot

      call start_trace_mark("find_segment_context: enter")
      ctx = 0
      if ((segment_id < 1) .or. (segment_id > self%num_segments)) then
         call start_trace_mark("find_segment_context: invalid segment")
         return
      end if
      if (self%segments(segment_id)%contexts%count <= 0) then
         call start_trace_mark("find_segment_context: no contexts")
         return
      end if

      if (allocated(self%segment_context_indices)) then
         if ((segment_id >= 1) .and. (segment_id <= size(self%segment_context_indices))) then
            if (allocated(self%segment_context_indices(segment_id)%slots)) then
               slot = hash_context_slot(self%call_stack, size(self%segment_context_indices(segment_id)%slots))
               start_slot = slot
               do
                  candidate_ctx = self%segment_context_indices(segment_id)%slots(slot)
                  if (candidate_ctx == 0) exit
                  if ((candidate_ctx >= 1) .and. (candidate_ctx <= self%segments(segment_id)%contexts%count)) then
                     if (self%segments(segment_id)%contexts%stacks(candidate_ctx)%equals(self%call_stack)) then
                        ctx = candidate_ctx
                        return
                     end if
                  end if

                  slot = slot + 1
                  if (slot > size(self%segment_context_indices(segment_id)%slots)) slot = 1
                  if (slot == start_slot) exit
               end do
            end if
         end if
      end if

      ctx = self%segments(segment_id)%contexts%find(self%call_stack)
      call start_trace_mark("find_segment_context: after contexts find")
      if (ctx > 0) then
         call ensure_segment_context_index(self, segment_id, self%segments(segment_id)%contexts%count)
         call start_trace_mark("find_segment_context: after ensure index")
         if (allocated(self%segment_context_indices(segment_id)%slots)) then
            call insert_segment_context_slot(self%segments(segment_id), &
                                             self%segment_context_indices(segment_id)%slots, self%call_stack, ctx)
            call start_trace_mark("find_segment_context: after insert slot")
         end if
      end if
      call start_trace_mark("find_segment_context: exit")
   end function find_segment_context

   integer function find_or_create_segment_context(self, segment_id) result(ctx)
      class(ftimer_t), intent(inout) :: self
      integer, intent(in) :: segment_id

      call start_trace_mark("find_or_create_segment_context: enter")
      ctx = find_segment_context(self, segment_id)
      call start_trace_mark("find_or_create_segment_context: after find_segment_context")
      if (ctx > 0) return

      call start_trace_mark("find_or_create_segment_context: before ensure_segment_context_index")
      call ensure_segment_context_index(self, segment_id, self%segments(segment_id)%contexts%count + 1)
      call start_trace_mark("find_or_create_segment_context: after ensure_segment_context_index")
      call start_trace_mark("find_or_create_segment_context: before contexts add")
      if (.not. allocated(self%segments(segment_id)%contexts%stacks)) then
         allocate (self%segments(segment_id)%contexts%stacks(FTIMER_CONTEXT_STORAGE_INITIAL_CAPACITY))
      else if (self%segments(segment_id)%contexts%count >= &
               size(self%segments(segment_id)%contexts%stacks)) then
         call grow_segment_context_stacks(self, segment_id)
      end if

      ctx = self%segments(segment_id)%contexts%count + 1
      self%segments(segment_id)%contexts%count = ctx
      self%segments(segment_id)%contexts%stacks(ctx)%depth = self%call_stack%depth
      if (allocated(self%segments(segment_id)%contexts%stacks(ctx)%ids)) then
         deallocate (self%segments(segment_id)%contexts%stacks(ctx)%ids)
      end if
      if (allocated(self%segments(segment_id)%contexts%stacks(ctx)%activation_tokens)) then
         deallocate (self%segments(segment_id)%contexts%stacks(ctx)%activation_tokens)
      end if
      if (self%call_stack%depth > 0) then
         allocate (self%segments(segment_id)%contexts%stacks(ctx)%ids(self%call_stack%depth))
         allocate (self%segments(segment_id)%contexts%stacks(ctx)%activation_tokens(self%call_stack%depth))
         self%segments(segment_id)%contexts%stacks(ctx)%ids = self%call_stack%ids(1:self%call_stack%depth)
         self%segments(segment_id)%contexts%stacks(ctx)%activation_tokens = &
            self%call_stack%activation_tokens(1:self%call_stack%depth)
      else
         allocate (self%segments(segment_id)%contexts%stacks(ctx)%ids(1))
         allocate (self%segments(segment_id)%contexts%stacks(ctx)%activation_tokens(1))
      end if
      call start_trace_mark("find_or_create_segment_context: after contexts add")
      call start_trace_mark("find_or_create_segment_context: before insert_segment_context_slot")
      call insert_segment_context_slot(self%segments(segment_id), &
                                       self%segment_context_indices(segment_id)%slots, self%call_stack, ctx)
      call start_trace_mark("find_or_create_segment_context: after insert_segment_context_slot")
      call start_trace_mark("find_or_create_segment_context: exit")
   end function find_or_create_segment_context

   integer function hash_name_slot(name, table_size) result(slot)
      character(len=*), intent(in) :: name
      integer, intent(in) :: table_size
      integer(int64) :: hash
      integer :: i
      integer :: trimmed_len

      if (table_size <= 0) error stop "ftimer internal hash_name_slot called with empty table"

      hash = 0_int64
      trimmed_len = len_trim(name)
      do i = 1, trimmed_len
         hash = modulo(FTIMER_NAME_HASH_MULTIPLIER*hash + int(iachar(name(i:i)), int64), &
                       FTIMER_NAME_HASH_MODULUS)
      end do

      ! Mix the polynomial hash before taking the table modulus so that
      ! sequential timer names do not create long low-bit probe clusters.
      hash = ieor(hash, shiftr(hash, 15))
      hash = modulo(FTIMER_NAME_HASH_MIX_MULTIPLIER*hash, FTIMER_NAME_HASH_MODULUS)
      hash = ieor(hash, shiftr(hash, 15))

      slot = 1 + int(modulo(hash, int(table_size, int64)))
   end function hash_name_slot

   integer function hash_id_slot(id, table_size) result(slot)
      integer, intent(in) :: id
      integer, intent(in) :: table_size
      integer(int64) :: hash

      if (table_size <= 0) error stop "ftimer internal hash_id_slot called with empty table"

      hash = int(id, int64)
      hash = ieor(hash, shiftr(hash, 15))
      hash = modulo(FTIMER_NAME_HASH_MIX_MULTIPLIER*hash, FTIMER_NAME_HASH_MODULUS)
      hash = ieor(hash, shiftr(hash, 15))

      slot = 1 + int(modulo(hash, int(table_size, int64)))
   end function hash_id_slot

   integer function hash_context_slot(stack, table_size) result(slot)
      type(ftimer_call_stack_t), intent(in) :: stack
      integer, intent(in) :: table_size
      integer(int64) :: hash
      integer :: i

      if (table_size <= 0) error stop "ftimer internal hash_context_slot called with empty table"

      hash = int(stack%depth, int64)
      do i = 1, stack%depth
         hash = modulo(FTIMER_NAME_HASH_MULTIPLIER*hash + int(stack%ids(i), int64), &
                       FTIMER_NAME_HASH_MODULUS)
      end do

      hash = ieor(hash, shiftr(hash, 15))
      hash = modulo(FTIMER_NAME_HASH_MIX_MULTIPLIER*hash, FTIMER_NAME_HASH_MODULUS)
      hash = ieor(hash, shiftr(hash, 15))

      slot = 1 + int(modulo(hash, int(table_size, int64)))
   end function hash_context_slot

   logical function has_active_timers(self) result(has_active)
      class(ftimer_t), intent(in) :: self

      has_active = self%call_stack%depth > 0
   end function has_active_timers

   subroutine normalize_name(name, trimmed_len, status, message)
      character(len=*), intent(in) :: name
      integer, intent(out) :: trimmed_len
      integer, intent(out) :: status
      character(len=*), intent(out) :: message
      integer :: i
      integer :: code
      character(len=32) :: position_text

      message = ''
      trimmed_len = len_trim(name)

      if (trimmed_len <= 0) then
         status = FTIMER_ERR_INVALID_NAME
         message = "ftimer timer name must not be empty"
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
            write (position_text, '(i0)') i
            message = "ftimer timer name contains control character at position "//trim(position_text)
            return
         end if
      end do

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

   subroutine start_trace_mark(message)
      character(len=*), intent(in) :: message
      character(len=8) :: enabled
      integer :: length
      integer :: status

      call get_environment_variable("FTIMER_START_TRACE", enabled, length=length, status=status)
      if ((status /= 0) .or. (length <= 0)) return
      if (enabled(1:1) == '0') return

      write (error_unit, '(a)') "ftimer-core: "//message
      flush (error_unit)
   end subroutine start_trace_mark

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

      ctx = find_segment_context(self, id)
      if (ctx <= 0) then
         error stop "ftimer internal stop_segment_with_now missing context"
      end if

      self%segments(id)%time(ctx) = self%segments(id)%time(ctx) + now - self%segments(id)%start_time(ctx)
      self%segments(id)%is_running(ctx) = .false.

      if (fire_callback .and. associated(self%on_event)) then
         call self%on_event(public_segment_id(self, id), ctx, FTIMER_EVENT_STOP, now, self%user_data)
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

end module ftimer_core
