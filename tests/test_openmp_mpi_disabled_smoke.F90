program ftimer_openmp_mpi_disabled_smoke
   use ftimer_openmp, only: ftimer_mpi_openmp_summary_t, ftimer_openmp_config_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_NOT_IMPLEMENTED, FTIMER_SUCCESS
   implicit none

   character(len=*), parameter :: csv_path = 'openmp_mpi_disabled_summary.csv'
   character(len=*), parameter :: report_path = 'openmp_mpi_disabled_summary.txt'
   type(ftimer_mpi_openmp_summary_t) :: summary
   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_t) :: timer
   integer :: ierr

   call delete_if_exists(report_path)
   call delete_if_exists(csv_path)

   config%max_lanes = 1
   call timer%init(config=config, ierr=ierr)
   call expect_status(ierr, FTIMER_SUCCESS, 1)

   call timer%mpi_openmp_summary(summary, ierr=ierr)
   call expect_status(ierr, FTIMER_ERR_NOT_IMPLEMENTED, 2)
   call expect_int(summary%num_ranks, 0, 3)
   call expect_int(summary%num_entries, 0, 4)

   call timer%print_mpi_openmp_summary(ierr=ierr)
   call expect_status(ierr, FTIMER_ERR_NOT_IMPLEMENTED, 5)

   call timer%write_mpi_openmp_summary(report_path, ierr=ierr)
   call expect_status(ierr, FTIMER_ERR_NOT_IMPLEMENTED, 6)
   call expect_file_absent(report_path, 7)

   call timer%write_mpi_openmp_summary_csv(csv_path, ierr=ierr)
   call expect_status(ierr, FTIMER_ERR_NOT_IMPLEMENTED, 8)
   call expect_file_absent(csv_path, 9)

   call timer%finalize(ierr=ierr)
   call expect_status(ierr, FTIMER_SUCCESS, 10)

contains

   subroutine expect_status(actual, expected, stop_code)
      integer, intent(in) :: actual
      integer, intent(in) :: expected
      integer, intent(in) :: stop_code

      if (actual /= expected) error stop stop_code
   end subroutine expect_status

   subroutine expect_int(actual, expected, stop_code)
      integer, intent(in) :: actual
      integer, intent(in) :: expected
      integer, intent(in) :: stop_code

      if (actual /= expected) error stop stop_code
   end subroutine expect_int

   subroutine expect_file_absent(path, stop_code)
      character(len=*), intent(in) :: path
      integer, intent(in) :: stop_code
      logical :: exists

      inquire (file=path, exist=exists)
      if (exists) error stop stop_code
   end subroutine expect_file_absent

   subroutine delete_if_exists(path)
      character(len=*), intent(in) :: path
      integer :: io
      integer :: unit
      logical :: exists

      inquire (file=path, exist=exists)
      if (.not. exists) return
      open (newunit=unit, file=path, status='old', iostat=io)
      if (io == 0) close (unit, status='delete')
   end subroutine delete_if_exists
end program ftimer_openmp_mpi_disabled_smoke
