module ftimer_types
   use, intrinsic :: iso_c_binding, only: c_ptr
   use, intrinsic :: iso_fortran_env, only: error_unit, int64
   implicit none
   private

   public :: FTIMER_SUCCESS
   public :: FTIMER_ERR_NOT_INIT
   public :: FTIMER_ERR_NOT_IMPLEMENTED
   public :: FTIMER_ERR_UNKNOWN
   public :: FTIMER_ERR_ACTIVE
   public :: FTIMER_ERR_MISMATCH
   public :: FTIMER_ERR_MPI_INCON
   public :: FTIMER_ERR_IO
   public :: FTIMER_ERR_INVALID_NAME
   public :: FTIMER_NAME_LEN
   public :: FTIMER_MISMATCH_STRICT
   public :: FTIMER_MISMATCH_WARN
   public :: FTIMER_MISMATCH_REPAIR
   public :: FTIMER_EVENT_START
   public :: FTIMER_EVENT_STOP
   public :: wp
   public :: ftimer_metadata_t
   public :: ftimer_context_diagnostic_t
   public :: ftimer_summary_entry_t
   public :: ftimer_summary_t
   public :: ftimer_mpi_summary_entry_t
   public :: ftimer_mpi_summary_t
   public :: ftimer_mpi_union_summary_entry_t
   public :: ftimer_mpi_union_summary_t
   public :: ftimer_call_stack_t
   public :: ftimer_context_list_t
   public :: ftimer_segment_t
   public :: ftimer_clock_func
   public :: ftimer_hook_proc

   integer, parameter :: FTIMER_SUCCESS = 0
   integer, parameter :: FTIMER_ERR_NOT_INIT = 1
   integer, parameter :: FTIMER_ERR_NOT_IMPLEMENTED = 2
   integer, parameter :: FTIMER_ERR_UNKNOWN = 3
   integer, parameter :: FTIMER_ERR_ACTIVE = 4
   integer, parameter :: FTIMER_ERR_MISMATCH = 5
   integer, parameter :: FTIMER_ERR_MPI_INCON = 6
   integer, parameter :: FTIMER_ERR_IO = 7
   integer, parameter :: FTIMER_ERR_INVALID_NAME = 8

   integer, parameter :: wp = selected_real_kind(15, 307)
   ! Retained as the pre-1.0 fixed-width compatibility threshold. Runtime timer
   ! names and metadata are allocatable-length strings and are not capped here.
   integer, parameter :: FTIMER_NAME_LEN = 64

   integer, parameter :: FTIMER_MISMATCH_STRICT = 1
   integer, parameter :: FTIMER_MISMATCH_WARN = 2
   integer, parameter :: FTIMER_MISMATCH_REPAIR = 3

   integer, parameter :: FTIMER_EVENT_START = 1
   integer, parameter :: FTIMER_EVENT_STOP = 2

   integer, parameter :: FTIMER_CALL_STACK_INITIAL_CAPACITY = 32
   integer, parameter :: FTIMER_CONTEXT_LIST_INITIAL_CAPACITY = 4

   type :: ftimer_metadata_t
      character(len=:), allocatable :: key
      character(len=:), allocatable :: value
   end type ftimer_metadata_t

   type :: ftimer_summary_entry_t
      character(len=:), allocatable :: name
      integer :: depth = 0
      real(wp) :: inclusive_time = 0.0_wp
      real(wp) :: self_time = 0.0_wp
      integer(int64) :: call_count = 0_int64
      real(wp) :: avg_time = 0.0_wp
      real(wp) :: pct_time = 0.0_wp
      ! Stable only within one produced summary object. Root nodes use parent_id = 0.
      integer :: node_id = 0
      integer :: parent_id = 0
      logical :: is_active = .false.
      integer :: timer_context_count = 0
   end type ftimer_summary_entry_t

   type :: ftimer_context_diagnostic_t
      character(len=:), allocatable :: name
      integer :: context_count = 0
   end type ftimer_context_diagnostic_t

   type :: ftimer_summary_t
      character(len=40) :: start_date = ''
      character(len=40) :: end_date = ''
      real(wp) :: total_time = 0.0_wp
      integer :: num_entries = 0
      type(ftimer_summary_entry_t), allocatable :: entries(:)
      logical :: has_active_timers = .false.
      integer :: total_contexts = 0
      integer :: max_contexts_per_timer = 0
      integer :: num_context_diagnostics = 0
      type(ftimer_context_diagnostic_t), allocatable :: context_diagnostics(:)
   end type ftimer_summary_t

   type :: ftimer_mpi_summary_entry_t
      character(len=:), allocatable :: name
      integer :: depth = 0
      real(wp) :: min_inclusive_time = 0.0_wp
      real(wp) :: max_inclusive_time = 0.0_wp
      real(wp) :: avg_inclusive_time = 0.0_wp
      real(wp) :: inclusive_imbalance = 1.0_wp
      real(wp) :: min_self_time = 0.0_wp
      real(wp) :: max_self_time = 0.0_wp
      real(wp) :: avg_self_time = 0.0_wp
      real(wp) :: self_imbalance = 1.0_wp
      integer(int64) :: min_call_count = 0_int64
      integer(int64) :: max_call_count = 0_int64
      real(wp) :: avg_call_count = 0.0_wp
      real(wp) :: min_pct_time = 0.0_wp
      real(wp) :: max_pct_time = 0.0_wp
      real(wp) :: avg_pct_time = 0.0_wp
      ! Stable only within one produced summary object. Root nodes use parent_id = 0.
      integer :: node_id = 0
      integer :: parent_id = 0
      integer :: min_inclusive_time_rank = -1
      integer :: max_inclusive_time_rank = -1
   end type ftimer_mpi_summary_entry_t

   type :: ftimer_mpi_summary_t
      integer :: num_ranks = 0
      integer :: num_entries = 0
      real(wp) :: min_total_time = 0.0_wp
      real(wp) :: max_total_time = 0.0_wp
      real(wp) :: avg_total_time = 0.0_wp
      real(wp) :: total_time_imbalance = 1.0_wp
      integer :: min_total_time_rank = -1
      integer :: max_total_time_rank = -1
      type(ftimer_mpi_summary_entry_t), allocatable :: entries(:)
   end type ftimer_mpi_summary_t

   type :: ftimer_mpi_union_summary_entry_t
      character(len=:), allocatable :: name
      integer :: depth = 0
      integer :: participating_rank_count = 0
      ! Missing ranks are derived as summary%num_ranks - participating_rank_count.
      ! Per-entry min/avg/max fields are over participating ranks only.
      real(wp) :: min_inclusive_time = 0.0_wp
      real(wp) :: max_inclusive_time = 0.0_wp
      real(wp) :: avg_inclusive_time = 0.0_wp
      real(wp) :: inclusive_imbalance = 1.0_wp
      real(wp) :: min_self_time = 0.0_wp
      real(wp) :: max_self_time = 0.0_wp
      real(wp) :: avg_self_time = 0.0_wp
      real(wp) :: self_imbalance = 1.0_wp
      integer(int64) :: min_call_count = 0_int64
      integer(int64) :: max_call_count = 0_int64
      real(wp) :: avg_call_count = 0.0_wp
      real(wp) :: min_pct_time = 0.0_wp
      real(wp) :: max_pct_time = 0.0_wp
      real(wp) :: avg_pct_time = 0.0_wp
      ! Stable only within one produced summary object. Root nodes use parent_id = 0.
      integer :: node_id = 0
      integer :: parent_id = 0
      integer :: min_inclusive_time_rank = -1
      integer :: max_inclusive_time_rank = -1
   end type ftimer_mpi_union_summary_entry_t

   type :: ftimer_mpi_union_summary_t
      integer :: num_ranks = 0
      integer :: num_entries = 0
      real(wp) :: min_total_time = 0.0_wp
      real(wp) :: max_total_time = 0.0_wp
      real(wp) :: avg_total_time = 0.0_wp
      real(wp) :: total_time_imbalance = 1.0_wp
      integer :: min_total_time_rank = -1
      integer :: max_total_time_rank = -1
      type(ftimer_mpi_union_summary_entry_t), allocatable :: entries(:)
   end type ftimer_mpi_union_summary_t

   type :: ftimer_call_stack_t
      integer :: depth = 0
      integer, allocatable :: ids(:)
      integer(int64), allocatable :: activation_tokens(:)
   contains
      procedure :: push => ftimer_call_stack_push
      procedure :: pop => ftimer_call_stack_pop
      procedure :: top => ftimer_call_stack_top
      procedure :: top_token => ftimer_call_stack_top_token
      procedure :: equals => ftimer_call_stack_equals
      procedure :: copy => ftimer_call_stack_copy
   end type ftimer_call_stack_t

   type :: ftimer_context_list_t
      integer :: count = 0
      type(ftimer_call_stack_t), allocatable :: stacks(:)
   contains
      procedure :: find => ftimer_context_list_find
      procedure :: add => ftimer_context_list_add
   end type ftimer_context_list_t

   type :: ftimer_segment_t
      character(len=:), allocatable :: name
      real(wp), allocatable :: time(:)
      real(wp), allocatable :: start_time(:)
      logical, allocatable :: is_running(:)
      integer(int64), allocatable :: call_count(:)
      type(ftimer_context_list_t) :: contexts
   end type ftimer_segment_t

   abstract interface
      function ftimer_clock_func() result(t)
         import :: wp
         real(wp) :: t
      end function ftimer_clock_func
   end interface

   abstract interface
      subroutine ftimer_hook_proc(timer_id, context_idx, event, timestamp, user_data)
         import :: c_ptr, wp
         integer, intent(in) :: timer_id
         integer, intent(in) :: context_idx
         integer, intent(in) :: event
         real(wp), intent(in) :: timestamp
         type(c_ptr), intent(in) :: user_data
      end subroutine ftimer_hook_proc
   end interface

contains

   subroutine ftimer_call_stack_push(self, id, activation_token)
      class(ftimer_call_stack_t), intent(inout) :: self
      integer, intent(in) :: id
      integer(int64), intent(in), optional :: activation_token
      integer, allocatable :: new_ids(:)
      integer(int64), allocatable :: new_tokens(:)
      integer :: new_capacity

      if (.not. allocated(self%ids)) then
         allocate (self%ids(FTIMER_CALL_STACK_INITIAL_CAPACITY))
         allocate (self%activation_tokens(FTIMER_CALL_STACK_INITIAL_CAPACITY))
      else if (self%depth >= size(self%ids)) then
         new_capacity = max(FTIMER_CALL_STACK_INITIAL_CAPACITY, 2*size(self%ids))
         allocate (new_ids(new_capacity))
         allocate (new_tokens(new_capacity))
         if (self%depth > 0) then
            new_ids(1:self%depth) = self%ids(1:self%depth)
            new_tokens(1:self%depth) = self%activation_tokens(1:self%depth)
         end if
         call move_alloc(new_ids, self%ids)
         call move_alloc(new_tokens, self%activation_tokens)
      end if

      self%depth = self%depth + 1
      self%ids(self%depth) = id
      if (present(activation_token)) then
         self%activation_tokens(self%depth) = activation_token
      else
         self%activation_tokens(self%depth) = 0_int64
      end if
   end subroutine ftimer_call_stack_push

   integer function ftimer_call_stack_pop(self, activation_token) result(id)
      class(ftimer_call_stack_t), intent(inout) :: self
      integer(int64), intent(out), optional :: activation_token

      id = 0
      if (present(activation_token)) activation_token = 0_int64
      if (self%depth <= 0) then
         self%depth = 0
         return
      end if

      id = self%ids(self%depth)
      if (present(activation_token)) activation_token = self%activation_tokens(self%depth)
      self%depth = self%depth - 1
   end function ftimer_call_stack_pop

   integer function ftimer_call_stack_top(self) result(id)
      class(ftimer_call_stack_t), intent(in) :: self

      id = 0
      if (self%depth <= 0) return
      id = self%ids(self%depth)
   end function ftimer_call_stack_top

   integer(int64) function ftimer_call_stack_top_token(self) result(activation_token)
      class(ftimer_call_stack_t), intent(in) :: self

      activation_token = 0_int64
      if (self%depth <= 0) return
      activation_token = self%activation_tokens(self%depth)
   end function ftimer_call_stack_top_token

   logical function ftimer_call_stack_equals(self, other) result(is_equal)
      class(ftimer_call_stack_t), intent(in) :: self
      class(ftimer_call_stack_t), intent(in) :: other

      is_equal = .false.
      if (self%depth /= other%depth) return
      if (self%depth == 0) then
         is_equal = .true.
         return
      end if

      is_equal = all(self%ids(1:self%depth) == other%ids(1:other%depth))
   end function ftimer_call_stack_equals

   subroutine ftimer_call_stack_copy(self, other)
      class(ftimer_call_stack_t), intent(inout) :: self
      class(ftimer_call_stack_t), intent(in) :: other

      call context_trace_mark("call_stack_copy: enter")
      self%depth = other%depth
      if (allocated(self%ids)) deallocate (self%ids)
      if (allocated(self%activation_tokens)) deallocate (self%activation_tokens)
      call context_trace_mark("call_stack_copy: after deallocate")

      if (other%depth > 0) then
         call context_trace_mark("call_stack_copy: before positive-depth allocate")
         allocate (self%ids(other%depth))
         allocate (self%activation_tokens(other%depth))
         self%ids = other%ids(1:other%depth)
         self%activation_tokens = other%activation_tokens(1:other%depth)
      else
         call context_trace_mark("call_stack_copy: before empty allocate")
         allocate (self%ids(1))
         allocate (self%activation_tokens(1))
      end if
      call context_trace_mark("call_stack_copy: exit")
   end subroutine ftimer_call_stack_copy

   integer function ftimer_context_list_find(self, stack) result(idx)
      class(ftimer_context_list_t), intent(in) :: self
      type(ftimer_call_stack_t), intent(in) :: stack

      idx = ftimer_context_list_find_impl(self, stack)
   end function ftimer_context_list_find

   integer function ftimer_context_list_find_impl(self, stack) result(idx)
      type(ftimer_context_list_t), intent(in) :: self
      type(ftimer_call_stack_t), intent(in) :: stack
      integer :: i

      idx = 0
      do i = 1, self%count
         if (self%stacks(i)%equals(stack)) then
            idx = i
            return
         end if
      end do
   end function ftimer_context_list_find_impl

   integer function ftimer_context_list_add(self, stack) result(idx)
      class(ftimer_context_list_t), intent(inout) :: self
      type(ftimer_call_stack_t), intent(in) :: stack

      idx = ftimer_context_list_add_impl(self, stack)
   end function ftimer_context_list_add

   integer function ftimer_context_list_add_impl(self, stack) result(idx)
      type(ftimer_context_list_t), intent(inout) :: self
      type(ftimer_call_stack_t), intent(in) :: stack
      integer :: existing

      call context_trace_mark("context_list_add_impl: enter")

      existing = ftimer_context_list_find_impl(self, stack)
      call context_trace_mark("context_list_add_impl: after find")
      if (existing > 0) then
         idx = existing
         return
      end if

      if (.not. allocated(self%stacks)) then
         call context_trace_mark("context_list_add_impl: before initial stacks allocate")
         allocate (self%stacks(FTIMER_CONTEXT_LIST_INITIAL_CAPACITY))
         call context_trace_mark("context_list_add_impl: after initial stacks allocate")
      else if (self%count >= size(self%stacks)) then
         call grow_context_list_stacks(self)
      end if

      self%count = self%count + 1
      call context_trace_mark("context_list_add_impl: before inline stack copy")
      self%stacks(self%count)%depth = stack%depth
      if (allocated(self%stacks(self%count)%ids)) deallocate (self%stacks(self%count)%ids)
      if (allocated(self%stacks(self%count)%activation_tokens)) deallocate (self%stacks(self%count)%activation_tokens)
      if (stack%depth > 0) then
         allocate (self%stacks(self%count)%ids(stack%depth))
         allocate (self%stacks(self%count)%activation_tokens(stack%depth))
         self%stacks(self%count)%ids = stack%ids(1:stack%depth)
         self%stacks(self%count)%activation_tokens = stack%activation_tokens(1:stack%depth)
      else
         allocate (self%stacks(self%count)%ids(1))
         allocate (self%stacks(self%count)%activation_tokens(1))
      end if
      call context_trace_mark("context_list_add_impl: after inline stack copy")
      idx = self%count
      call context_trace_mark("context_list_add_impl: exit")
   end function ftimer_context_list_add_impl

   subroutine grow_context_list_stacks(self)
      class(ftimer_context_list_t), intent(inout) :: self
      type(ftimer_call_stack_t), allocatable :: new_stacks(:)
      integer :: new_capacity

      new_capacity = max(FTIMER_CONTEXT_LIST_INITIAL_CAPACITY, 2*size(self%stacks))
      allocate (new_stacks(new_capacity))
      if (self%count > 0) then
         new_stacks(1:self%count) = self%stacks(1:self%count)
      end if
      call move_alloc(new_stacks, self%stacks)
   end subroutine grow_context_list_stacks

   subroutine context_trace_mark(message)
      character(len=*), intent(in) :: message
      character(len=8) :: enabled
      integer :: length
      integer :: status

      call get_environment_variable("FTIMER_START_TRACE", enabled, length=length, status=status)
      if ((status /= 0) .or. (length <= 0)) return
      if (enabled(1:1) == '0') return

      write (error_unit, '(a)') "ftimer-types: "//message
      flush (error_unit)
   end subroutine context_trace_mark

end module ftimer_types
