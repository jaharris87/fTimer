module ftimer
   use ftimer_core, only: ftimer_t
   use ftimer_types, only: ftimer_metadata_t, ftimer_summary_t
   implicit none
   private

   public :: ftimer_init
   public :: ftimer_finalize
   public :: ftimer_start
   public :: ftimer_stop
   public :: ftimer_start_id
   public :: ftimer_stop_id
   public :: ftimer_lookup
   public :: ftimer_reset
   public :: ftimer_get_summary
   public :: ftimer_print_summary
   public :: ftimer_write_summary
   public :: ftimer_default_instance

   type(ftimer_t), save, target :: ftimer_default_instance

contains

   subroutine ftimer_init(ierr, comm, mismatch_mode)
      integer, intent(out), optional :: ierr
      integer, intent(in), optional :: comm
      integer, intent(in), optional :: mismatch_mode

      call ftimer_default_instance%init(ierr=ierr, comm=comm, mismatch_mode=mismatch_mode)
   end subroutine ftimer_init

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

end module ftimer
