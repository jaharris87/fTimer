program ftimer_installed_openmp_api_consumer
   use ftimer_openmp, only: FTIMER_OPENMP_MODE_THREAD_LANES, ftimer_openmp_config_t, &
                            ftimer_openmp_parallel_region_t, ftimer_openmp_summary_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS
   implicit none

   character(len=*), parameter :: summary_csv_path = 'installed_openmp_summary.csv'
   character(len=*), parameter :: summary_report_path = 'installed_openmp_summary.txt'
   integer :: duplicate_id
   integer :: i
   integer :: ierr
   integer :: j
   integer :: lookup_id
   integer :: reset_id
   integer :: timer_id
   integer :: unknown_id
   integer :: ids(20)
   character(len=32) :: name
   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_parallel_region_t) :: region
   type(ftimer_openmp_summary_t) :: summary
   type(ftimer_openmp_t) :: timer

   config%mode = FTIMER_OPENMP_MODE_THREAD_LANES
   config%max_lanes = 4
   config%max_worker_diagnostics = 8

   call timer%init(config=config, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 1

   call timer%register_timer("consumer_openmp_api_work", timer_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 2
   if (timer_id <= 0) error stop 3

   call timer%register_timer("consumer_openmp_api_work", duplicate_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 4
   if (duplicate_id /= timer_id) error stop 5

   call timer%lookup_timer("consumer_openmp_api_work", duplicate_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 6
   if (duplicate_id /= timer_id) error stop 7

   call timer%lookup_timer("consumer_openmp_api_missing", unknown_id, ierr=ierr)
   if (ierr /= FTIMER_ERR_UNKNOWN) error stop 8
   if (unknown_id /= 0) error stop 9

   do i = 1, size(ids)
      write (name, '("consumer_openmp_api_bulk_",i0)') i
      call timer%register_timer(trim(name), ids(i), ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 23
      if (ids(i) <= 0) error stop 24
      if (ids(i) == timer_id) error stop 25
      do j = 1, i - 1
         if (ids(i) == ids(j)) error stop 26
      end do
      call timer%lookup_timer(trim(name), lookup_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 27
      if (lookup_id /= ids(i)) error stop 28
   end do

   call timer%begin_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 10

   call timer%start_id(timer_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 11

   call timer%stop_id(timer_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 12

   call timer%end_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 13

   call timer%reset(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 14

   call timer%lookup_timer("consumer_openmp_api_work", reset_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 15
   if (reset_id /= timer_id) error stop 16

   call timer%start_id(timer_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 17
   call timer%stop_id(timer_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 36
   call timer%get_openmp_summary(summary, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 38
   if (summary%num_entries /= 1) error stop 39
   call delete_if_exists(summary_report_path)
   call delete_if_exists(summary_csv_path)
   call timer%write_openmp_summary(summary_report_path, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 40
   call timer%write_openmp_summary_csv(summary_csv_path, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 41
   call delete_if_exists(summary_report_path)
   call delete_if_exists(summary_csv_path)

   do i = 1, size(ids)
      write (name, '("consumer_openmp_api_bulk_",i0)') i
      call timer%lookup_timer(trim(name), lookup_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 18
      if (lookup_id /= ids(i)) error stop 19
      call timer%start_id(ids(i), ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 20
      call timer%stop_id(ids(i), ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 37
   end do

   call timer%register_timer("consumer_openmp_api_after_reset", reset_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 21
   if (reset_id == timer_id) error stop 22
   do i = 1, size(ids)
      if (reset_id == ids(i)) error stop 28
   end do

   call timer%finalize(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 29

   call timer%init(config=config, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 30

   call timer%start_id(timer_id, ierr=ierr)
   if (ierr /= FTIMER_ERR_UNKNOWN) error stop 31

   do i = 1, size(ids)
      call timer%stop_id(ids(i), ierr=ierr)
      if (ierr /= FTIMER_ERR_UNKNOWN) error stop 32
   end do

   call timer%register_timer("consumer_openmp_api_after_reinit", reset_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 33
   if (reset_id == timer_id) error stop 34

   call timer%finalize(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 35

contains

   subroutine delete_if_exists(path)
      character(len=*), intent(in) :: path
      integer :: io
      integer :: unit

      open (newunit=unit, file=path, status='old', iostat=io)
      if (io == 0) close (unit, status='delete')
   end subroutine delete_if_exists
end program ftimer_installed_openmp_api_consumer
