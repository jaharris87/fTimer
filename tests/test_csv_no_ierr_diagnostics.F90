program test_csv_no_ierr_diagnostics
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_start, ftimer_stop, ftimer_write_summary_csv
   use ftimer_types, only: FTIMER_SUCCESS
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Finalize, MPI_Init
#endif
   implicit none

   character(len=*), parameter :: bad_csv_path = 'csv_no_ierr_bad_append.csv'
   character(len=*), parameter :: bad_text = 'format_version,summary_kind,record_type'//new_line('a')
   integer :: ierr

   call delete_if_exists(bad_csv_path)
   call write_text_file(bad_csv_path, bad_text)

#ifdef FTIMER_USE_MPI
   call MPI_Init(ierr)
   if (ierr /= 0) error stop 1
#endif

   call ftimer_init(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 2
   call ftimer_start('diagnostic', ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 3
   call ftimer_stop('diagnostic', ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 4

   call ftimer_write_summary_csv(bad_csv_path, append=.true.)
   if (.not. same_text(read_file_text(bad_csv_path), bad_text)) error stop 5

   call ftimer_finalize(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 6

#ifdef FTIMER_USE_MPI
   call MPI_Finalize(ierr)
   if (ierr /= 0) error stop 7
#endif

   call delete_if_exists(bad_csv_path)

contains

   subroutine delete_if_exists(path)
      character(len=*), intent(in) :: path
      integer :: io
      integer :: unit

      open (newunit=unit, file=path, status='old', iostat=io)
      if (io == 0) close (unit, status='delete')
   end subroutine delete_if_exists

   subroutine write_text_file(path, text)
      character(len=*), intent(in) :: path
      character(len=*), intent(in) :: text
      integer :: io
      integer :: unit

      open (newunit=unit, file=path, status='replace', access='stream', form='unformatted', &
            action='write', iostat=io)
      if (io /= 0) error stop 8
      write (unit, iostat=io) text
      if (io /= 0) error stop 9
      close (unit)
   end subroutine write_text_file

   logical function same_text(actual, expected) result(matches)
      character(len=*), intent(in) :: actual
      character(len=*), intent(in) :: expected

      matches = (len(actual) == len(expected))
      if (matches) matches = actual == expected
   end function same_text

   function read_file_text(path) result(text)
      character(len=*), intent(in) :: path
      character(len=:), allocatable :: text
      character(len=1) :: ch
      integer :: io
      integer :: unit

      text = ''
      open (newunit=unit, file=path, status='old', access='stream', form='unformatted', &
            action='read', iostat=io)
      if (io /= 0) error stop 10
      do
         read (unit, iostat=io) ch
         if (io /= 0) exit
         text = text//ch
      end do
      close (unit)
   end function read_file_text

end program test_csv_no_ierr_diagnostics
