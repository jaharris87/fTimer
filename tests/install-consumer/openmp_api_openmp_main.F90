program ftimer_installed_openmp_api_openmp_consumer
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_parallel_region_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_SUCCESS
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
   implicit none

   integer :: ierr
   integer :: timer_id
   integer :: worker_bad
   integer :: worker_seen
   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_parallel_region_t) :: region
   type(ftimer_openmp_t) :: timer

   call omp_set_dynamic(.false.)

   config%max_lanes = 0
   config%max_worker_diagnostics = 1

   call timer%init(config=config, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 1

   call timer%register_timer("consumer_openmp_api_parallel_work", timer_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 2

   call timer%begin_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 5

   worker_bad = 0
   worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
   if (omp_get_thread_num() /= 0) then
      worker_seen = worker_seen + 1

      call timer%start_id(timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1

      call timer%reset(ierr=ierr)
      if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1

      call timer%stop_id(timer_id)
   end if
!$omp end parallel

   if (worker_seen <= 0) error stop 3
   if (worker_bad /= 0) error stop 4

   call timer%end_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 6

   call timer%finalize()
end program ftimer_installed_openmp_api_openmp_consumer
