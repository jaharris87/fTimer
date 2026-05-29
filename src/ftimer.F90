module ftimer
   use, intrinsic :: iso_fortran_env, only: error_unit, int64
   use ftimer_core, only: ftimer_internal_start_scope_activation, ftimer_internal_stop_scope_activation, ftimer_t
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_SUCCESS, ftimer_metadata_t, ftimer_mpi_summary_t, &
                           ftimer_mpi_union_summary_t, ftimer_summary_t
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Comm
#endif
   implicit none
   private

   public :: ftimer_guard_t
   public :: ftimer_init
   public :: ftimer_finalize
   public :: ftimer_start
   public :: ftimer_stop
   public :: ftimer_scope
   public :: ftimer_start_id
   public :: ftimer_stop_id
   public :: ftimer_lookup
   public :: ftimer_reset
   public :: ftimer_get_summary
   public :: ftimer_mpi_summary
   public :: ftimer_mpi_union_summary
   public :: ftimer_print_summary
   public :: ftimer_write_summary
   public :: ftimer_write_summary_csv
   public :: ftimer_print_mpi_summary
   public :: ftimer_write_mpi_summary
   public :: ftimer_write_mpi_summary_csv
   public :: ftimer_print_mpi_union_summary
   public :: ftimer_write_mpi_union_summary
   public :: ftimer_default_instance

#ifdef FTIMER_USE_MPI
   interface ftimer_init
      module procedure ftimer_init_with_integer_comm
      module procedure ftimer_init_with_mpi_comm
   end interface
#else
   interface ftimer_init
      module procedure ftimer_init_with_integer_comm
   end interface
#endif

   type(ftimer_t), save, target :: ftimer_default_instance

   type :: ftimer_guard_t
      private
      type(ftimer_t), pointer :: timer => null()
      integer :: timer_id = 0
      integer(int64) :: activation_token = 0_int64
      logical :: active = .false.
   contains
      procedure, public :: stop => ftimer_guard_stop
      final :: ftimer_guard_finalize
      procedure, private :: assign => ftimer_guard_assign
      generic, public :: assignment(=) => assign
   end type ftimer_guard_t

contains

   subroutine ftimer_scope(guard, name, ierr)
      type(ftimer_guard_t), intent(inout) :: guard
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr
      integer :: id
      integer(int64) :: activation_token

      if (guard%active) then
         call report_guard_status(ierr, FTIMER_ERR_ACTIVE, "ftimer_scope called with an active guard; state unchanged")
         return
      end if

      call clear_guard(guard)
      call ftimer_internal_start_scope_activation(ftimer_default_instance, name, id, activation_token, ierr=ierr)

      if ((id <= 0) .or. (activation_token == 0_int64)) return

      guard%timer => ftimer_default_instance
      guard%timer_id = id
      guard%activation_token = activation_token
      guard%active = .true.
   end subroutine ftimer_scope

   subroutine ftimer_guard_stop(self, ierr)
      class(ftimer_guard_t), intent(inout) :: self
      integer, intent(out), optional :: ierr
      integer :: status

      if (.not. self%active) then
         if (present(ierr)) ierr = FTIMER_SUCCESS
         return
      end if

      if (.not. associated(self%timer)) then
         call clear_guard(self)
         if (present(ierr)) ierr = FTIMER_SUCCESS
         return
      end if

      status = ftimer_internal_stop_scope_activation(self%timer, self%timer_id, self%activation_token, ierr=ierr)
      if (status == FTIMER_SUCCESS) call clear_guard(self)
   end subroutine ftimer_guard_stop

   subroutine ftimer_guard_finalize(self)
      type(ftimer_guard_t), intent(inout) :: self

      call self%stop()
   end subroutine ftimer_guard_finalize

   subroutine ftimer_guard_assign(lhs, rhs)
      class(ftimer_guard_t), intent(inout) :: lhs
      type(ftimer_guard_t), intent(in) :: rhs

      if (lhs%active .or. rhs%active) then
         write (error_unit, '(a)') "ftimer guard assignment is unsupported; active ownership was not copied"
      end if

      if (.not. lhs%active) call clear_guard(lhs)
   end subroutine ftimer_guard_assign

   subroutine clear_guard(guard)
      class(ftimer_guard_t), intent(inout) :: guard

      nullify (guard%timer)
      guard%timer_id = 0
      guard%activation_token = 0_int64
      guard%active = .false.
   end subroutine clear_guard

   subroutine report_guard_status(ierr, code, message)
      integer, intent(out), optional :: ierr
      integer, intent(in) :: code
      character(len=*), intent(in) :: message

      if (present(ierr)) then
         ierr = code
      else
         write (error_unit, '(a)') trim(message)
      end if
   end subroutine report_guard_status

   subroutine ftimer_init_with_integer_comm(comm, mismatch_mode, ierr)
      integer, intent(in), optional :: comm
      integer, intent(in), optional :: mismatch_mode
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%init(comm=comm, mismatch_mode=mismatch_mode, ierr=ierr)
   end subroutine ftimer_init_with_integer_comm

#ifdef FTIMER_USE_MPI
   subroutine ftimer_init_with_mpi_comm(comm, mismatch_mode, ierr)
      type(MPI_Comm), intent(in) :: comm
      integer, intent(in), optional :: mismatch_mode
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%init(comm=comm, mismatch_mode=mismatch_mode, ierr=ierr)
   end subroutine ftimer_init_with_mpi_comm
#endif

   subroutine ftimer_finalize(ierr)
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%finalize(ierr=ierr)
   end subroutine ftimer_finalize

   subroutine ftimer_start(name, ierr)
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%start(name, ierr=ierr)
   end subroutine ftimer_start

   subroutine ftimer_stop(name, ierr)
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%stop(name, ierr=ierr)
   end subroutine ftimer_stop

   subroutine ftimer_start_id(id, ierr)
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%start_id(id, ierr=ierr)
   end subroutine ftimer_start_id

   subroutine ftimer_stop_id(id, ierr)
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%stop_id(id, ierr=ierr)
   end subroutine ftimer_stop_id

   integer function ftimer_lookup(name, ierr) result(id)
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      id = ftimer_default_instance%lookup(name, ierr=ierr)
   end function ftimer_lookup

   subroutine ftimer_reset(ierr)
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%reset(ierr=ierr)
   end subroutine ftimer_reset

   subroutine ftimer_get_summary(summary, ierr)
      type(ftimer_summary_t), intent(out) :: summary
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%get_summary(summary, ierr=ierr)
   end subroutine ftimer_get_summary

   subroutine ftimer_mpi_summary(summary, ierr)
      type(ftimer_mpi_summary_t), intent(out) :: summary
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%mpi_summary(summary, ierr=ierr)
   end subroutine ftimer_mpi_summary

   subroutine ftimer_mpi_union_summary(summary, ierr)
      type(ftimer_mpi_union_summary_t), intent(out) :: summary
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%mpi_union_summary(summary, ierr=ierr)
   end subroutine ftimer_mpi_union_summary

   subroutine ftimer_print_summary(unit, metadata, ierr)
      integer, intent(in), optional :: unit
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%print_summary(unit=unit, metadata=metadata, ierr=ierr)
   end subroutine ftimer_print_summary

   subroutine ftimer_write_summary(filename, append, metadata, ierr)
      character(len=*), intent(in) :: filename
      logical, intent(in), optional :: append
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%write_summary(filename, append=append, metadata=metadata, ierr=ierr)
   end subroutine ftimer_write_summary

   subroutine ftimer_write_summary_csv(filename, append, metadata, ierr)
      character(len=*), intent(in) :: filename
      logical, intent(in), optional :: append
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%write_summary_csv(filename, append=append, metadata=metadata, ierr=ierr)
   end subroutine ftimer_write_summary_csv

   subroutine ftimer_print_mpi_summary(unit, metadata, ierr)
      integer, intent(in), optional :: unit
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%print_mpi_summary(unit=unit, metadata=metadata, ierr=ierr)
   end subroutine ftimer_print_mpi_summary

   subroutine ftimer_write_mpi_summary(filename, append, metadata, ierr)
      character(len=*), intent(in) :: filename
      logical, intent(in), optional :: append
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%write_mpi_summary(filename, append=append, metadata=metadata, ierr=ierr)
   end subroutine ftimer_write_mpi_summary

   subroutine ftimer_write_mpi_summary_csv(filename, append, metadata, ierr)
      character(len=*), intent(in) :: filename
      logical, intent(in), optional :: append
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%write_mpi_summary_csv(filename, append=append, metadata=metadata, ierr=ierr)
   end subroutine ftimer_write_mpi_summary_csv

   subroutine ftimer_print_mpi_union_summary(unit, metadata, ierr)
      integer, intent(in), optional :: unit
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%print_mpi_union_summary(unit=unit, metadata=metadata, ierr=ierr)
   end subroutine ftimer_print_mpi_union_summary

   subroutine ftimer_write_mpi_union_summary(filename, append, metadata, ierr)
      character(len=*), intent(in) :: filename
      logical, intent(in), optional :: append
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%write_mpi_union_summary(filename, append=append, metadata=metadata, ierr=ierr)
   end subroutine ftimer_write_mpi_union_summary

end module ftimer
