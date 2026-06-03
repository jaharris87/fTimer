program ftimer_openmp_api_smoke
#ifdef FTIMER_USE_OPENMP
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
#endif
   use ftimer_openmp, only: FTIMER_OPENMP_MODE_THREAD_LANES, ftimer_openmp_config_t, &
                            ftimer_openmp_parallel_region_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_INVALID_NAME, FTIMER_ERR_MISMATCH, &
                           FTIMER_ERR_NOT_INIT, FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS
   implicit none

   call check_preinit_and_config()
   call check_catalog_lifecycle()
#ifdef FTIMER_USE_OPENMP
   call check_parallel_rejections()
   call check_thread_lane_runtime()
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
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer

      call timer%register_timer("before_init", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_INIT, 1)

      call timer%lookup_timer("before_init", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_INIT, 68)

      call timer%reset(ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_INIT, 69)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_INIT, 70)

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_INIT, 71)

      call timer%start_id(1, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_INIT, 2)

      call timer%stop_id(1, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_INIT, 72)

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
      integer :: after_direct_reinit_id
      integer :: duplicate_id
      integer :: direct_reinit_id
      integer :: i
      integer :: ierr
      integer :: j
      integer :: lookup_id
      integer :: old_id
      integer :: reset_id
      integer :: timer_id
      integer :: ids(20)
      character(len=32) :: name
      type(ftimer_openmp_config_t) :: bad_config
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

      call timer%lookup_timer("", lookup_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_INVALID_NAME, 73)
      if (lookup_id /= 0) error stop 74

      call timer%lookup_timer(" leading", lookup_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_INVALID_NAME, 75)
      if (lookup_id /= 0) error stop 76

      call timer%lookup_timer("bad"//achar(9)//"name", lookup_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_INVALID_NAME, 77)
      if (lookup_id /= 0) error stop 78

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
         do j = 1, i - 1
            if (ids(i) == ids(j)) error stop 21
         end do
         call timer%lookup_timer(trim(name), lookup_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 22)
         if (lookup_id /= ids(i)) error stop 23
      end do

      call timer%lookup_timer("work", old_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 24)
      if (old_id /= timer_id) error stop 25

      bad_config = config
      bad_config%mode = -1
      call timer%init(config=bad_config, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 79)

      call timer%lookup_timer("work", old_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 80)
      if (old_id /= timer_id) error stop 81

      call timer%start_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 82)

      call timer%stop_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 89)

      do i = 1, size(ids)
         write (name, '("bulk_",i0)') i
         call timer%lookup_timer(trim(name), lookup_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 83)
         if (lookup_id /= ids(i)) error stop 84
      end do

      call timer%start_id(0, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 85)

      call timer%start_id(-1, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 86)

      call timer%stop_id(0, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 87)

      call timer%stop_id(-1, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 88)

      call timer%reset(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 26)

      call timer%lookup_timer("work", reset_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 27)
      if (reset_id /= timer_id) error stop 28

      do i = 1, size(ids)
         write (name, '("bulk_",i0)') i
         call timer%lookup_timer(trim(name), lookup_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 29)
         if (lookup_id /= ids(i)) error stop 30
         call timer%start_id(ids(i), ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 31)
         call timer%stop_id(ids(i), ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 90)
      end do

      call timer%start_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 32)
      call timer%stop_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 91)

      call timer%register_timer("after_reset", reset_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 33)
      if (reset_id == timer_id) error stop 34
      do i = 1, size(ids)
         if (reset_id == ids(i)) error stop 35
      end do

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 36)

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 37)

      call timer%register_timer("before_direct_reinit", direct_reinit_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 38)
      if (direct_reinit_id == timer_id) error stop 39
      if (direct_reinit_id == reset_id) error stop 40
      do i = 1, size(ids)
         if (direct_reinit_id == ids(i)) error stop 41
      end do

      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 42)

      call timer%lookup_timer("before_direct_reinit", lookup_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 43)
      if (lookup_id /= 0) error stop 44

      call timer%lookup_timer("work", lookup_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 45)
      if (lookup_id /= 0) error stop 46

      call timer%start_id(direct_reinit_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 47)

      call timer%stop_id(direct_reinit_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 48)

      call timer%start_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 49)

      call timer%register_timer("after_direct_reinit", after_direct_reinit_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 50)
      if (after_direct_reinit_id == timer_id) error stop 51
      if (after_direct_reinit_id == direct_reinit_id) error stop 52
      do i = 1, size(ids)
         if (after_direct_reinit_id == ids(i)) error stop 53
      end do

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 54)

      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 55)

      call timer%start_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 56)

      call timer%lookup_timer("after_direct_reinit", lookup_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 57)
      if (lookup_id /= 0) error stop 58

      call timer%start_id(after_direct_reinit_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 59)

      call timer%stop_id(after_direct_reinit_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 60)

      do i = 1, size(ids)
         call timer%stop_id(ids(i), ierr=ierr)
         call expect_status(ierr, FTIMER_ERR_UNKNOWN, 61)
      end do

      call timer%register_timer("after_reinit", reset_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 62)
      if (reset_id == timer_id) error stop 63
      if (reset_id == direct_reinit_id) error stop 64
      if (reset_id == after_direct_reinit_id) error stop 65
      do i = 1, size(ids)
         if (reset_id == ids(i)) error stop 66
      end do

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 67)
   end subroutine check_catalog_lifecycle

#ifdef FTIMER_USE_OPENMP
   subroutine check_parallel_rejections()
      integer :: ierr
      integer :: local_id
      integer :: timer_id
      integer :: master_seen
      integer :: worker_bad
      integer :: worker_seen
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: local_region
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
      master_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr, local_id, local_region) &
!$omp& reduction(+:worker_bad, worker_seen, master_seen)
      if (omp_get_thread_num() == 0) then
         master_seen = master_seen + 1

         local_id = -1
         call timer%register_timer("parallel_master_created", local_id, ierr=ierr)
         if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1
         if (local_id /= 0) worker_bad = worker_bad + 1

         call timer%reset(ierr=ierr)
         if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1

         call timer%finalize(ierr=ierr)
         if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1

         call timer%init(config=config, ierr=ierr)
         if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1

         call timer%begin_parallel_region(local_region, ierr=ierr)
         if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1

         call timer%end_parallel_region(local_region, ierr=ierr)
         if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1

         local_id = -1
         call timer%lookup_timer("parallel_work", local_id, ierr=ierr)
         if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1
         if (local_id /= 0) worker_bad = worker_bad + 1
      else
         worker_seen = worker_seen + 1

         local_id = -1
         call timer%lookup_timer("parallel_work", local_id, ierr=ierr)
         if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1
         if (local_id /= 0) worker_bad = worker_bad + 1

         call timer%start_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1

         call timer%reset(ierr=ierr)
         if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1

         call timer%stop_id(timer_id)
      end if
!$omp end parallel

      if (master_seen /= 1) error stop 42
      if (worker_seen <= 0) error stop 42
      if (worker_bad /= 0) error stop 43

      call timer%lookup_timer("parallel_work", local_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 44)
      if (local_id /= timer_id) error stop 45

      call timer%lookup_timer("parallel_master_created", local_id, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 46)

      call timer%finalize()
   end subroutine check_parallel_rejections

   subroutine check_thread_lane_runtime()
      integer :: capacity_bad
      integer :: ierr
      integer :: other_id
      integer :: timer_id
      integer :: worker_bad
      integer :: worker_seen
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: forgotten_timer
      type(ftimer_openmp_t) :: limited_timer
      type(ftimer_openmp_t) :: timer

      call omp_set_dynamic(.false.)

      config%max_lanes = 4
      config%max_worker_diagnostics = 4

      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 100)

      call timer%register_timer("lane_work", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 101)

      call timer%register_timer("other_lane_work", other_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 102)

      call timer%start_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 103)

      call timer%reset(ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 104)

      call timer%stop_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 105)

      call timer%reset(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 106)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 107)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 137)

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 138)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 139)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(3) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      worker_seen = worker_seen + 1
      call timer%start_id(timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      call timer%stop_id(timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
!$omp end parallel

      if (worker_seen /= 3) error stop 108
      if (worker_bad /= 0) error stop 109

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 110)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 111)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(3) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         call timer%start_id(other_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         call timer%stop_id(other_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 112
      if (worker_bad /= 0) error stop 113

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 114)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 115)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         call timer%start_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp barrier
      if (omp_get_thread_num() == 0) then
         worker_seen = worker_seen + 1
         call timer%stop_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_ERR_MISMATCH) worker_bad = worker_bad + 1
      end if
!$omp barrier
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         call timer%stop_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 2) error stop 116
      if (worker_bad /= 0) error stop 117

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 118)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         call timer%start_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_ERR_ACTIVE) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 119
      if (worker_bad /= 0) error stop 120

      call forgotten_timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 121)

      call forgotten_timer%register_timer("forgotten", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 122)

      call forgotten_timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 123)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         call forgotten_timer%start_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 124
      if (worker_bad /= 0) error stop 125

      call forgotten_timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 126)

      call forgotten_timer%reset(ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 127)

      call forgotten_timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 136)

      config%max_lanes = 2
      call limited_timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 128)

      call limited_timer%register_timer("limited", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 129)

      call limited_timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 130)

      capacity_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:capacity_bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         call limited_timer%start_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_ERR_UNKNOWN) capacity_bad = capacity_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 131
      if (capacity_bad /= 0) error stop 132

      call limited_timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 133)

      call limited_timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 134)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 135)
   end subroutine check_thread_lane_runtime
#endif

end program ftimer_openmp_api_smoke
