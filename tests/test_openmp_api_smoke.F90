program ftimer_openmp_api_smoke
#ifdef FTIMER_USE_OPENMP
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
#endif
   use ftimer_openmp, only: FTIMER_OPENMP_MODE_THREAD_LANES, ftimer_openmp_config_t, &
                            ftimer_openmp_parallel_region_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_INVALID_NAME, FTIMER_ERR_NOT_IMPLEMENTED, &
                           FTIMER_ERR_NOT_INIT, FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS
   implicit none

   call check_preinit_and_config()
   call check_catalog_lifecycle()
#ifdef FTIMER_USE_OPENMP
   call check_parallel_rejections()
#endif

contains

   subroutine expect_status(actual, expected, stop_code)
      integer, intent(in) :: actual
      integer, intent(in) :: expected
      integer, intent(in) :: stop_code

      if (actual /= expected) error stop stop_code
   end subroutine expect_status

   subroutine expect_positive(value, stop_code)
      integer, intent(in) :: value
      integer, intent(in) :: stop_code

      if (value <= 0) error stop stop_code
   end subroutine expect_positive

   subroutine check_preinit_and_config()
      integer :: ierr
      integer :: timer_id
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer

      call timer%register_timer("before_init", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_INIT, 1)

      call timer%start_id(1, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_INIT, 2)

      config%mode = -1
      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 3)

      config = ftimer_openmp_config_t()
      config%max_lanes = -1
      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 4)

      config = ftimer_openmp_config_t()
      config%max_worker_diagnostics = -1
      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 5)
   end subroutine check_preinit_and_config

   subroutine check_catalog_lifecycle()
      integer :: duplicate_id
      integer :: i
      integer :: ierr
      integer :: old_id
      integer :: reset_id
      integer :: timer_id
      integer :: ids(20)
      character(len=32) :: name
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer

      config%mode = FTIMER_OPENMP_MODE_THREAD_LANES
      config%max_lanes = 0
      config%max_worker_diagnostics = 2

      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 10)

      call timer%register_timer("", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_INVALID_NAME, 11)

      call timer%register_timer(" leading", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_INVALID_NAME, 12)

      call timer%register_timer("bad"//achar(9)//"name", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_INVALID_NAME, 13)

      call timer%register_timer("work", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 14)
      call expect_positive(timer_id, 15)

      call timer%register_timer("work", duplicate_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 16)
      if (duplicate_id /= timer_id) error stop 17

      do i = 1, size(ids)
         write (name, '("bulk_",i0)') i
         call timer%register_timer(trim(name), ids(i), ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 18)
         call expect_positive(ids(i), 19)
         if (ids(i) == timer_id) error stop 20
      end do

      call timer%lookup_timer("work", old_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 21)
      if (old_id /= timer_id) error stop 22

      call timer%reset(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 23)

      call timer%lookup_timer("work", reset_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 24)
      if (reset_id /= timer_id) error stop 25

      call timer%start_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_IMPLEMENTED, 26)

      call timer%register_timer("after_reset", reset_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 27)
      if (reset_id == timer_id) error stop 28

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_IMPLEMENTED, 29)

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_IMPLEMENTED, 30)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 31)

      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 32)

      call timer%start_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 33)

      call timer%register_timer("after_reinit", reset_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 34)
      if (reset_id == timer_id) error stop 35

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 36)
   end subroutine check_catalog_lifecycle

#ifdef FTIMER_USE_OPENMP
   subroutine check_parallel_rejections()
      integer :: ierr
      integer :: timer_id
      integer :: worker_bad
      integer :: worker_seen
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer

      call omp_set_dynamic(.false.)

      config%max_lanes = 0
      config%max_worker_diagnostics = 1

      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 40)

      call timer%register_timer("parallel_work", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 41)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      if (omp_get_thread_num() /= 0) then
         worker_seen = worker_seen + 1

         call timer%start_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_ERR_NOT_IMPLEMENTED) worker_bad = worker_bad + 1

         call timer%reset(ierr=ierr)
         if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1

         call timer%stop_id(timer_id)
      end if
!$omp end parallel

      if (worker_seen <= 0) error stop 42
      if (worker_bad /= 0) error stop 43

      call timer%finalize()
   end subroutine check_parallel_rejections
#endif

end program ftimer_openmp_api_smoke
