program ftimer_installed_openmp_api_consumer
   use ftimer_openmp, only: FTIMER_OPENMP_MODE_THREAD_LANES, ftimer_openmp_config_t, &
                            ftimer_openmp_parallel_region_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_NOT_IMPLEMENTED, FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS
   implicit none

   integer :: duplicate_id
   integer :: ierr
   integer :: timer_id
   integer :: unknown_id
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

   call timer%finalize(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 15
end program ftimer_installed_openmp_api_consumer
