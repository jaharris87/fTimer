program ftimer_installed_openmp_api_consumer
   use ftimer_openmp, only: FTIMER_OPENMP_MODE_THREAD_LANES, ftimer_openmp_config_t, &
                            ftimer_openmp_parallel_region_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_NOT_IMPLEMENTED, FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS
   implicit none

   integer :: duplicate_id
   integer :: i
   integer :: ierr
   integer :: reset_id
   integer :: timer_id
   integer :: unknown_id
   integer :: ids(20)
   character(len=32) :: name
   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_parallel_region_t) :: region
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

   call timer%begin_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_ERR_NOT_IMPLEMENTED) error stop 10

   call timer%start_id(timer_id, ierr=ierr)
   if (ierr /= FTIMER_ERR_NOT_IMPLEMENTED) error stop 11

   call timer%stop_id(timer_id, ierr=ierr)
   if (ierr /= FTIMER_ERR_NOT_IMPLEMENTED) error stop 12

   call timer%end_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_ERR_NOT_IMPLEMENTED) error stop 13

   call timer%reset(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 14

   call timer%lookup_timer("consumer_openmp_api_work", reset_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 15
   if (reset_id /= timer_id) error stop 16

   call timer%start_id(timer_id, ierr=ierr)
   if (ierr /= FTIMER_ERR_NOT_IMPLEMENTED) error stop 17

   call timer%register_timer("consumer_openmp_api_after_reset", reset_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 18
   if (reset_id == timer_id) error stop 19

   do i = 1, size(ids)
      write (name, '("consumer_openmp_api_bulk_",i0)') i
      call timer%register_timer(trim(name), ids(i), ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 20
      if (ids(i) <= 0) error stop 21
      if (ids(i) == timer_id) error stop 22
   end do

   call timer%finalize(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 23

   call timer%init(config=config, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 24

   call timer%start_id(timer_id, ierr=ierr)
   if (ierr /= FTIMER_ERR_UNKNOWN) error stop 25

   call timer%register_timer("consumer_openmp_api_after_reinit", reset_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 26
   if (reset_id == timer_id) error stop 27

   call timer%finalize(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 28
end program ftimer_installed_openmp_api_consumer
