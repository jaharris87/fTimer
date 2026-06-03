program ftimer_openmp_api_ierr_silence
#ifdef FTIMER_USE_OPENMP
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
#endif
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_parallel_region_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_INVALID_NAME, FTIMER_ERR_NOT_INIT, &
                           FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS
   implicit none

   integer :: ierr
   integer :: timer_id
   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_parallel_region_t) :: region
   type(ftimer_openmp_t) :: timer

   call timer%register_timer("before_init", timer_id, ierr=ierr)
   if (ierr /= FTIMER_ERR_NOT_INIT) error stop 1

   config%mode = -1
   call timer%init(config=config, ierr=ierr)
   if (ierr /= FTIMER_ERR_UNKNOWN) error stop 2

   config = ftimer_openmp_config_t()
   call timer%init(config=config, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 3

   call timer%register_timer("", timer_id, ierr=ierr)
   if (ierr /= FTIMER_ERR_INVALID_NAME) error stop 4

   call timer%lookup_timer("missing", timer_id, ierr=ierr)
   if (ierr /= FTIMER_ERR_UNKNOWN) error stop 5

   call timer%register_timer("work", timer_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 6

   call timer%begin_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 7

#ifdef FTIMER_USE_OPENMP
   call check_parallel_ierr_silence(timer, timer_id)
#endif

   call timer%end_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 8

   call timer%finalize()

contains

#ifdef FTIMER_USE_OPENMP
   subroutine check_parallel_ierr_silence(timer, timer_id)
      type(ftimer_openmp_t), intent(inout) :: timer
      integer, intent(in) :: timer_id
      integer :: local_ierr
      integer :: local_id
      integer :: status_bad
      integer :: worker_seen

      call omp_set_dynamic(.false.)

      status_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(local_ierr, local_id) &
!$omp& reduction(+:status_bad, worker_seen)
      if (omp_get_thread_num() == 0) then
         call timer%reset(ierr=local_ierr)
         if (local_ierr /= FTIMER_ERR_ACTIVE) status_bad = status_bad + 1

         call timer%register_timer("master_parallel", local_id, ierr=local_ierr)
         if (local_ierr /= FTIMER_ERR_ACTIVE) status_bad = status_bad + 1
         if (local_id /= 0) status_bad = status_bad + 1
      else
         worker_seen = worker_seen + 1

         call timer%start_id(timer_id, ierr=local_ierr)
         if (local_ierr /= FTIMER_SUCCESS) status_bad = status_bad + 1

         call timer%stop_id(timer_id, ierr=local_ierr)
         if (local_ierr /= FTIMER_SUCCESS) status_bad = status_bad + 1
      end if
!$omp end parallel

      if (worker_seen <= 0) error stop 20
      if (status_bad /= 0) error stop 21
   end subroutine check_parallel_ierr_silence
#endif

end program ftimer_openmp_api_ierr_silence
