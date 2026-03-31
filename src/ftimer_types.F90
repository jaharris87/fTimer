module ftimer_types
   use, intrinsic :: iso_c_binding, only: c_ptr
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
   public :: ftimer_summary_entry_t
   public :: ftimer_summary_t
   public :: ftimer_mpi_summary_entry_t
   public :: ftimer_mpi_summary_t
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
   integer, parameter :: FTIMER_NAME_LEN = 64

   integer, parameter :: FTIMER_MISMATCH_STRICT = 1
   integer, parameter :: FTIMER_MISMATCH_WARN = 2
   integer, parameter :: FTIMER_MISMATCH_REPAIR = 3

   integer, parameter :: FTIMER_EVENT_START = 1
   integer, parameter :: FTIMER_EVENT_STOP = 2

   integer, parameter :: FTIMER_CALL_STACK_INITIAL_CAPACITY = 32
   integer, parameter :: FTIMER_CONTEXT_LIST_INITIAL_CAPACITY = 4

   type :: ftimer_metadata_t
      character(len=FTIMER_NAME_LEN) :: key = ''
      character(len=FTIMER_NAME_LEN) :: value = ''
   end type ftimer_metadata_t

   type :: ftimer_summary_entry_t
      character(len=FTIMER_NAME_LEN) :: name = ''
      integer :: depth = 0
      real(wp) :: inclusive_time = 0.0_wp
      real(wp) :: self_time = 0.0_wp
      integer :: call_count = 0
      real(wp) :: avg_time = 0.0_wp
      real(wp) :: pct_time = 0.0_wp
      ! Stable only within one produced summary object. Root nodes use parent_id = 0.
      integer :: node_id = 0
      integer :: parent_id = 0
   end type ftimer_summary_entry_t

   type :: ftimer_summary_t
      character(len=40) :: start_date = ''
      character(len=40) :: end_date = ''
      real(wp) :: total_time = 0.0_wp
      integer :: num_entries = 0
      type(ftimer_summary_entry_t), allocatable :: entries(:)
   end type ftimer_summary_t

   type :: ftimer_mpi_summary_entry_t
      character(len=FTIMER_NAME_LEN) :: name = ''
      integer :: depth = 0
      real(wp) :: min_inclusive_time = 0.0_wp
      real(wp) :: max_inclusive_time = 0.0_wp
      real(wp) :: avg_inclusive_time = 0.0_wp
      real(wp) :: inclusive_imbalance = 1.0_wp
      real(wp) :: min_self_time = 0.0_wp
      real(wp) :: max_self_time = 0.0_wp
      real(wp) :: avg_self_time = 0.0_wp
      real(wp) :: self_imbalance = 1.0_wp
      integer :: min_call_count = 0
      integer :: max_call_count = 0
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

   type :: ftimer_call_stack_t
      integer :: depth = 0
      integer, allocatable :: ids(:)
   contains
      procedure :: push => ftimer_call_stack_push
      procedure :: pop => ftimer_call_stack_pop
      procedure :: top => ftimer_call_stack_top
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
      character(len=FTIMER_NAME_LEN) :: name = ''
      real(wp), allocatable :: time(:)
      real(wp), allocatable :: start_time(:)
      logical, allocatable :: is_running(:)
      integer, allocatable :: call_count(:)
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

   subroutine ftimer_call_stack_push(self, id)
      class(ftimer_call_stack_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, allocatable :: new_ids(:)
      integer :: new_capacity

      if (.not. allocated(self%ids)) then
         allocate (self%ids(FTIMER_CALL_STACK_INITIAL_CAPACITY))
      else if (self%depth >= size(self%ids)) then
         new_capacity = max(FTIMER_CALL_STACK_INITIAL_CAPACITY, 2*size(self%ids))
         allocate (new_ids(new_capacity))
         if (self%depth > 0) then
            new_ids(1:self%depth) = self%ids(1:self%depth)
         end if
         call move_alloc(new_ids, self%ids)
      end if

      self%depth = self%depth + 1
      self%ids(self%depth) = id
   end subroutine ftimer_call_stack_push

   integer function ftimer_call_stack_pop(self) result(id)
      class(ftimer_call_stack_t), intent(inout) :: self

      id = 0
      if (self%depth <= 0) then
         self%depth = 0
         return
      end if

      id = self%ids(self%depth)
      self%depth = self%depth - 1
   end function ftimer_call_stack_pop

   integer function ftimer_call_stack_top(self) result(id)
      class(ftimer_call_stack_t), intent(in) :: self

      id = 0
      if (self%depth <= 0) return
      id = self%ids(self%depth)
   end function ftimer_call_stack_top

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
      class(ftimer_call_stack_t), intent(out) :: self
      class(ftimer_call_stack_t), intent(in) :: other

      self%depth = other%depth
      if (allocated(self%ids)) deallocate (self%ids)

      if (other%depth > 0) then
         allocate (self%ids(other%depth))
         self%ids = other%ids(1:other%depth)
      else if (allocated(other%ids)) then
         allocate (self%ids(0))
      end if
   end subroutine ftimer_call_stack_copy

   integer function ftimer_context_list_find(self, stack) result(idx)
      class(ftimer_context_list_t), intent(in) :: self
      type(ftimer_call_stack_t), intent(in) :: stack
      integer :: i

      idx = 0
      do i = 1, self%count
         if (self%stacks(i)%equals(stack)) then
            idx = i
            return
         end if
      end do
   end function ftimer_context_list_find

   integer function ftimer_context_list_add(self, stack) result(idx)
      class(ftimer_context_list_t), intent(inout) :: self
      type(ftimer_call_stack_t), intent(in) :: stack
      type(ftimer_call_stack_t), allocatable :: new_stacks(:)
      integer :: existing
      integer :: new_capacity

      existing = self%find(stack)
      if (existing > 0) then
         idx = existing
         return
      end if

      if (.not. allocated(self%stacks)) then
         allocate (self%stacks(FTIMER_CONTEXT_LIST_INITIAL_CAPACITY))
      else if (self%count >= size(self%stacks)) then
         new_capacity = max(FTIMER_CONTEXT_LIST_INITIAL_CAPACITY, 2*size(self%stacks))
         allocate (new_stacks(new_capacity))
         if (self%count > 0) then
            new_stacks(1:self%count) = self%stacks(1:self%count)
         end if
         call move_alloc(new_stacks, self%stacks)
      end if

      self%count = self%count + 1
      call self%stacks(self%count)%copy(stack)
      idx = self%count
   end function ftimer_context_list_add

end module ftimer_types
