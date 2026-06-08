program ftimer_openmp_api_smoke
   use, intrinsic :: iso_fortran_env, only: int64
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Finalize, MPI_Init
#endif
#ifdef FTIMER_USE_OPENMP
   use omp_lib, only: omp_get_thread_num, omp_in_parallel, omp_set_dynamic, omp_set_num_threads
#endif
   use ftimer_openmp, only: FTIMER_OPENMP_MODE_THREAD_LANES, ftimer_openmp_config_t, &
                            ftimer_openmp_parallel_region_t, ftimer_openmp_summary_t, &
                            ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_INVALID_NAME, FTIMER_ERR_MISMATCH, &
                           FTIMER_ERR_NOT_INIT, FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS, wp
   implicit none

   integer :: mpi_ierr
   real(wp), save :: fake_lane_time(0:4) = 0.0_wp

#ifdef FTIMER_USE_MPI
   call MPI_Init(mpi_ierr)
#endif

   call check_preinit_and_config()
   call check_catalog_lifecycle()
#ifdef FTIMER_USE_OPENMP
   call check_parallel_rejections()
   call check_thread_lane_runtime()
   call check_worker_hotpath_scaling_invariants()
   call check_worker_team_size_summary_cache()
#endif

#ifdef FTIMER_USE_MPI
   call MPI_Finalize(mpi_ierr)
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

   subroutine expect_count(actual, expected, stop_code)
      integer(int64), intent(in) :: actual
      integer(int64), intent(in) :: expected
      integer, intent(in) :: stop_code

      if (actual /= expected) error stop stop_code
   end subroutine expect_count

   subroutine expect_time(actual, expected, stop_code)
      real(wp), intent(in) :: actual
      real(wp), intent(in) :: expected
      integer, intent(in) :: stop_code

      if (abs(actual - expected) > 1.0e-12_wp) error stop stop_code
   end subroutine expect_time

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
      integer(int64) :: call_count
      integer :: lookup_id
      integer :: old_id
      integer :: reset_id
      integer :: timer_id
      real(wp) :: elapsed
      integer :: ids(20)
      character(len=32) :: name
      type(ftimer_openmp_config_t) :: bad_config
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer

      config%mode = FTIMER_OPENMP_MODE_THREAD_LANES
      config%max_lanes = 3
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

      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 92)

      fake_lane_time(0) = 5.0_wp
      call timer%start_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 93)

      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 97)

      fake_lane_time(0) = 8.0_wp
      call timer%stop_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 94)

      call timer%test_lane_total_call_count(0, timer_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 95)
      call expect_count(call_count, 1_int64, 96)

      call timer%test_lane_total_time(0, timer_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 98)
      call expect_time(elapsed, 3.0_wp, 99)

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

      config%max_lanes = 3
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
      integer(int64) :: call_count
      integer :: child_id
      integer :: ierr
      integer :: mismatch_child_id
      integer :: mismatch_parent_id
      integer :: nested_status
      integer :: other_id
      integer :: parent_id
      integer :: second_id
      integer :: common_parent_id
      integer :: grand_a_id
      integer :: grand_b_id
      integer :: shared_leaf_id
      integer :: shared_child_id
      integer :: shared_parent_a_id
      integer :: shared_parent_b_id
      integer :: timer_id
      integer :: default_id
      integer :: worker_bad
      integer :: worker_seen
      integer :: stack_ids(2)
      logical :: is_running
      real(wp) :: elapsed
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_parallel_region_t) :: second_region
      type(ftimer_openmp_parallel_region_t) :: stale_region
      type(ftimer_openmp_t) :: forgotten_timer
      type(ftimer_openmp_t) :: limited_timer
      type(ftimer_openmp_t) :: second_timer
      type(ftimer_openmp_t) :: default_timer
      type(ftimer_openmp_t) :: timer

      call omp_set_dynamic(.false.)
      call omp_set_num_threads(2)

      config%max_lanes = 4
      config%max_worker_diagnostics = 4

      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 100)

      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 188)

      call timer%register_timer("lane_work", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 101)

      call timer%register_timer("other_lane_work", other_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 102)

      call timer%register_timer("nested_parent", parent_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 141)

      call timer%register_timer("nested_child", child_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 142)

      call timer%register_timer("mismatch_parent", mismatch_parent_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 189)

      call timer%register_timer("mismatch_child", mismatch_child_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 190)

      call timer%register_timer("shared_parent_a", shared_parent_a_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 253)

      call timer%register_timer("shared_parent_b", shared_parent_b_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 254)

      call timer%register_timer("shared_child", shared_child_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 255)

      call timer%register_timer("grand_a", grand_a_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 272)

      call timer%register_timer("grand_b", grand_b_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 273)

      call timer%register_timer("common_parent", common_parent_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 274)

      call timer%register_timer("shared_leaf", shared_leaf_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 275)

      fake_lane_time(0) = 1.0_wp
      call timer%start_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 103)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 140)

      call timer%reset(ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 104)

      fake_lane_time(0) = 3.0_wp
      call timer%stop_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 105)

      call timer%test_lane_total_call_count(0, timer_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 191)
      call expect_count(call_count, 1_int64, 192)

      call timer%test_lane_total_time(0, timer_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 193)
      call expect_time(elapsed, 2.0_wp, 194)

      call timer%test_lane_is_running(0, timer_id, is_running, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 195)
      if (is_running) error stop 196

      call timer%reset(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 106)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 107)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 137)

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 138)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 143)

      stale_region = region
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 144)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 177)

      call timer%end_parallel_region(stale_region, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 178)

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 179)

      call second_timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 180)

      call second_timer%register_timer("foreign", second_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 181)

      call second_timer%begin_parallel_region(second_region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 182)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 183)

      call timer%end_parallel_region(second_region, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 184)

      call second_timer%end_parallel_region(second_region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 185)

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 186)

      call second_timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 187)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 139)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      worker_seen = worker_seen + 1
      if (omp_get_thread_num() == 0) then
         fake_lane_time(1) = 1.0_wp
      else
         fake_lane_time(2) = 10.0_wp
      end if
      call timer%start_id(timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      if (omp_get_thread_num() == 0) then
         fake_lane_time(1) = 4.0_wp
      else
         fake_lane_time(2) = 17.0_wp
      end if
      call timer%stop_id(timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
!$omp end parallel

      if (worker_seen /= 2) error stop 108
      if (worker_bad /= 0) error stop 109

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 110)

      call timer%test_lane_total_call_count(0, timer_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 146)
      call expect_count(call_count, 0_int64, 147)

      call timer%test_lane_total_time(0, timer_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 220)
      call expect_time(elapsed, 0.0_wp, 221)

      call timer%test_lane_total_call_count(1, timer_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 148)
      call expect_count(call_count, 1_int64, 149)

      call timer%test_lane_total_time(1, timer_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 216)
      call expect_time(elapsed, 3.0_wp, 217)

      call timer%test_lane_total_call_count(2, timer_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 150)
      call expect_count(call_count, 1_int64, 151)

      call timer%test_lane_total_time(2, timer_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 218)
      call expect_time(elapsed, 7.0_wp, 219)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 292)

      worker_seen = 0

!$omp parallel num_threads(2) default(shared) reduction(+:worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         call timer%stop_id(timer_id)
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 293

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_MISMATCH, 294)

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 295)

      config = ftimer_openmp_config_t()
      config%max_worker_diagnostics = 4
      call default_timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 236)

      call default_timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 237)

      call default_timer%register_timer("default_lane_work", default_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 238)

      call default_timer%begin_parallel_region(second_region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 239)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      worker_seen = worker_seen + 1
      if (omp_get_thread_num() == 0) then
         fake_lane_time(1) = 20.0_wp
      else
         fake_lane_time(2) = 40.0_wp
      end if
      call default_timer%start_id(default_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      if (omp_get_thread_num() == 0) then
         fake_lane_time(1) = 23.0_wp
      else
         fake_lane_time(2) = 47.0_wp
      end if
      call default_timer%stop_id(default_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
!$omp end parallel

      if (worker_seen /= 2) error stop 240
      if (worker_bad /= 0) error stop 241

      call default_timer%end_parallel_region(second_region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 242)

      call default_timer%test_lane_total_call_count(1, default_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 243)
      call expect_count(call_count, 1_int64, 244)

      call default_timer%test_lane_total_time(1, default_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 245)
      call expect_time(elapsed, 3.0_wp, 246)

      call default_timer%test_lane_total_call_count(2, default_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 247)
      call expect_count(call_count, 1_int64, 248)

      call default_timer%test_lane_total_time(2, default_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 249)
      call expect_time(elapsed, 7.0_wp, 250)

      call default_timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 251)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 111)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
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

      call timer%test_lane_total_call_count(1, other_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 152)
      call expect_count(call_count, 0_int64, 153)

      call timer%test_lane_total_call_count(2, other_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 154)
      call expect_count(call_count, 1_int64, 155)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 156)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         fake_lane_time(2) = 10.0_wp
         call timer%start_id(parent_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 12.0_wp
         call timer%start_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 15.0_wp
         call timer%stop_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 20.0_wp
         call timer%stop_id(parent_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 157
      if (worker_bad /= 0) error stop 158

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 159)

      call timer%test_lane_total_call_count(2, parent_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 160)
      call expect_count(call_count, 1_int64, 161)

      call timer%test_lane_parent_call_count(2, child_id, parent_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 162)
      call expect_count(call_count, 1_int64, 163)

      call timer%test_lane_total_time(2, parent_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 197)
      call expect_time(elapsed, 10.0_wp, 198)

      call timer%test_lane_parent_total_time(2, child_id, parent_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 199)
      call expect_time(elapsed, 3.0_wp, 200)

      call timer%test_lane_is_running(2, parent_id, is_running, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 201)
      if (is_running) error stop 202

      call timer%test_lane_is_running(2, child_id, is_running, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 203)
      if (is_running) error stop 204

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 256)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         fake_lane_time(2) = 50.0_wp
         call timer%start_id(shared_parent_a_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 51.0_wp
         call timer%start_id(shared_child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 55.0_wp
         call timer%stop_id(shared_child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 60.0_wp
         call timer%stop_id(shared_parent_a_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1

         fake_lane_time(2) = 70.0_wp
         call timer%start_id(shared_parent_b_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 72.0_wp
         call timer%start_id(shared_child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 79.0_wp
         call timer%stop_id(shared_child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 81.0_wp
         call timer%stop_id(shared_parent_b_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 257
      if (worker_bad /= 0) error stop 258

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 259)

      call timer%test_lane_parent_call_count(2, shared_child_id, shared_parent_a_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 260)
      call expect_count(call_count, 1_int64, 261)

      call timer%test_lane_parent_total_time(2, shared_child_id, shared_parent_a_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 262)
      call expect_time(elapsed, 4.0_wp, 263)

      call timer%test_lane_parent_call_count(2, shared_child_id, shared_parent_b_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 264)
      call expect_count(call_count, 1_int64, 265)

      call timer%test_lane_parent_total_time(2, shared_child_id, shared_parent_b_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 266)
      call expect_time(elapsed, 7.0_wp, 267)

      call timer%test_lane_total_call_count(2, shared_child_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 268)
      call expect_count(call_count, 2_int64, 269)

      call timer%test_lane_total_time(2, shared_child_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 270)
      call expect_time(elapsed, 11.0_wp, 271)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 276)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         fake_lane_time(2) = 90.0_wp
         call timer%start_id(grand_a_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 91.0_wp
         call timer%start_id(common_parent_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 92.0_wp
         call timer%start_id(shared_leaf_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 96.0_wp
         call timer%stop_id(shared_leaf_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 98.0_wp
         call timer%stop_id(common_parent_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 100.0_wp
         call timer%stop_id(grand_a_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1

         fake_lane_time(2) = 110.0_wp
         call timer%start_id(grand_b_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 111.0_wp
         call timer%start_id(common_parent_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 112.0_wp
         call timer%start_id(shared_leaf_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 119.0_wp
         call timer%stop_id(shared_leaf_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 121.0_wp
         call timer%stop_id(common_parent_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 123.0_wp
         call timer%stop_id(grand_b_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 277
      if (worker_bad /= 0) error stop 278

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 279)

      stack_ids = [grand_a_id, common_parent_id]
      call timer%test_lane_stack_call_count(2, shared_leaf_id, stack_ids, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 280)
      call expect_count(call_count, 1_int64, 281)

      call timer%test_lane_stack_total_time(2, shared_leaf_id, stack_ids, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 282)
      call expect_time(elapsed, 4.0_wp, 283)

      stack_ids = [grand_b_id, common_parent_id]
      call timer%test_lane_stack_call_count(2, shared_leaf_id, stack_ids, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 284)
      call expect_count(call_count, 1_int64, 285)

      call timer%test_lane_stack_total_time(2, shared_leaf_id, stack_ids, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 286)
      call expect_time(elapsed, 7.0_wp, 287)

      call timer%test_lane_total_call_count(2, shared_leaf_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 288)
      call expect_count(call_count, 2_int64, 289)

      call timer%test_lane_total_time(2, shared_leaf_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 290)
      call expect_time(elapsed, 11.0_wp, 291)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 205)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         fake_lane_time(2) = 30.0_wp
         call timer%start_id(mismatch_parent_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 32.0_wp
         call timer%start_id(mismatch_child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 35.0_wp
         call timer%stop_id(mismatch_parent_id, ierr=ierr)
         if (ierr /= FTIMER_ERR_MISMATCH) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 206
      if (worker_bad /= 0) error stop 207

      call timer%test_lane_is_running(2, mismatch_parent_id, is_running, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 222)
      if (.not. is_running) error stop 223

      call timer%test_lane_is_running(2, mismatch_child_id, is_running, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 224)
      if (.not. is_running) error stop 225

      call timer%test_lane_total_time(2, mismatch_parent_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 226)
      call expect_time(elapsed, 0.0_wp, 227)

      call timer%test_lane_parent_total_time(2, mismatch_child_id, mismatch_parent_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 228)
      call expect_time(elapsed, 0.0_wp, 229)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         fake_lane_time(2) = 38.0_wp
         call timer%stop_id(mismatch_child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 40.0_wp
         call timer%stop_id(mismatch_parent_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 230
      if (worker_bad /= 0) error stop 231

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 208)

      call timer%test_lane_total_call_count(2, mismatch_parent_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 209)
      call expect_count(call_count, 1_int64, 210)

      call timer%test_lane_parent_call_count(2, mismatch_child_id, mismatch_parent_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 211)
      call expect_count(call_count, 1_int64, 212)

      call timer%test_lane_total_time(2, mismatch_parent_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 232)
      call expect_time(elapsed, 10.0_wp, 233)

      call timer%test_lane_parent_total_time(2, mismatch_child_id, mismatch_parent_id, elapsed, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 234)
      call expect_time(elapsed, 6.0_wp, 235)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 213)

      nested_status = FTIMER_SUCCESS

!$omp parallel num_threads(2) default(shared) private(ierr)
      if (omp_get_thread_num() == 1) then
!$omp parallel num_threads(1) default(shared) private(ierr)
         call timer%start_id(timer_id, ierr=ierr)
         nested_status = ierr
!$omp end parallel
      end if
!$omp end parallel

      call expect_status(nested_status, FTIMER_ERR_ACTIVE, 214)

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 215)

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

      call forgotten_timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 252)

      worker_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         call forgotten_timer%stop_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 164
      if (worker_bad /= 0) error stop 165

      call forgotten_timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 166)

      call forgotten_timer%reset(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 167)

      call forgotten_timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 168)

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
      if (omp_get_thread_num() == 0) then
         worker_seen = worker_seen + 1
         call limited_timer%start_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) capacity_bad = capacity_bad + 1
         call limited_timer%stop_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) capacity_bad = capacity_bad + 1
      else
         worker_seen = worker_seen + 1
         call limited_timer%start_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_ERR_UNKNOWN) capacity_bad = capacity_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 2) error stop 131
      if (capacity_bad /= 0) error stop 132

      call limited_timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 133)

      call limited_timer%test_lane_total_call_count(1, timer_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 169)
      call expect_count(call_count, 1_int64, 170)

      call limited_timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 171)

      capacity_bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:capacity_bad, worker_seen)
      if (omp_get_thread_num() == 0) then
         worker_seen = worker_seen + 1
         call limited_timer%start_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) capacity_bad = capacity_bad + 1
         call limited_timer%stop_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) capacity_bad = capacity_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 172
      if (capacity_bad /= 0) error stop 173

      call limited_timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 174)

      call limited_timer%test_lane_total_call_count(1, timer_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 175)
      call expect_count(call_count, 2_int64, 176)

      call limited_timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 134)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 135)
   end subroutine check_thread_lane_runtime

   subroutine check_worker_hotpath_scaling_invariants()
      integer, parameter :: num_contexts = 64
      integer, parameter :: num_catalog_timers = 256
      integer :: bad
      integer(int64) :: call_count
      integer :: catalog_ids(num_catalog_timers)
      integer :: duplicate_id
      integer :: ierr
      integer :: j
      integer :: lookup_id
      integer :: parent_ids(num_contexts)
      integer :: worker_seen
      integer :: work_id
      real(wp) :: elapsed
      character(len=16) :: name
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer

      call omp_set_dynamic(.false.)
      config%max_lanes = 3
      config%max_worker_diagnostics = 4

      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1300)
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1301)

      do j = 1, num_catalog_timers
         write (name, '("indexed_",i4.4)') j
         call timer%register_timer(name, catalog_ids(j), ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 1302)
      end do

      do j = 1, num_catalog_timers
         write (name, '("indexed_",i4.4)') j
         call timer%lookup_timer(name, lookup_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 1303)
         if (lookup_id /= catalog_ids(j)) error stop 1304
         call timer%register_timer(name, duplicate_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 1305)
         if (duplicate_id /= catalog_ids(j)) error stop 1306
      end do

      do j = 1, num_contexts
         write (name, '("parent_",i4.4)') j
         call timer%register_timer(name, parent_ids(j), ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 1307)
      end do
      call timer%register_timer("indexed_worker", work_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1308)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1309)

      bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr, j) reduction(+:bad, worker_seen)
      if (omp_get_thread_num() == 1) then
         worker_seen = worker_seen + 1
         do j = 1, num_contexts
            fake_lane_time(2) = real(10*j, wp)
            call timer%start_id(parent_ids(j), ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
            fake_lane_time(2) = fake_lane_time(2) + 0.25_wp
            call timer%start_id(work_id, ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
            fake_lane_time(2) = fake_lane_time(2) + 1.0_wp
            call timer%stop_id(work_id, ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
            fake_lane_time(2) = fake_lane_time(2) + 0.25_wp
            call timer%stop_id(parent_ids(j), ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
         end do

         do j = 1, num_contexts
            fake_lane_time(2) = real(1000 + 10*j, wp)
            call timer%start_id(parent_ids(j), ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
            fake_lane_time(2) = fake_lane_time(2) + 0.25_wp
            call timer%start_id(work_id, ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
            fake_lane_time(2) = fake_lane_time(2) + 1.0_wp
            call timer%stop_id(work_id, ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
            fake_lane_time(2) = fake_lane_time(2) + 0.25_wp
            call timer%stop_id(parent_ids(j), ierr=ierr)
            if (ierr /= FTIMER_SUCCESS) bad = bad + 1
         end do
      end if
!$omp end parallel

      if (worker_seen <= 0) error stop 1310
      if (bad /= 0) error stop 1311

      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1312)

      call timer%test_lane_total_call_count(2, work_id, call_count, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1313)
      call expect_count(call_count, int(2*num_contexts, int64), 1314)

      do j = 1, num_contexts
         call timer%test_lane_parent_call_count(2, work_id, parent_ids(j), call_count, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 1315)
         call expect_count(call_count, 2_int64, 1316)

         call timer%test_lane_parent_total_time(2, work_id, parent_ids(j), elapsed, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 1317)
         call expect_time(elapsed, 2.0_wp, 1318)

         call timer%test_lane_total_time(2, parent_ids(j), elapsed, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 1320)
         call expect_time(elapsed, 3.0_wp, 1321)
      end do

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1319)
   end subroutine check_worker_hotpath_scaling_invariants

   subroutine check_worker_team_size_summary_cache()
      integer :: bad
      integer :: ierr
      integer :: lane
      integer :: shared_id
      integer :: shared_idx
      integer :: solo_id
      integer :: solo_idx
      integer :: solo_seen
      integer :: warm_id
      integer :: warm_idx
      integer :: warm_seen
      integer :: worker_seen
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_summary_t) :: summary
      type(ftimer_openmp_t) :: timer

      call omp_set_dynamic(.false.)
      config%max_lanes = 5
      config%max_worker_diagnostics = 4

      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1400)
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1401)

      call timer%register_timer("summary_shared", shared_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1402)
      call timer%register_timer("summary_solo", solo_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1403)
      call timer%register_timer("summary_warm", warm_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1433)

      fake_lane_time(0) = 100.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1404)

      bad = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr, lane) reduction(+:bad, worker_seen)
      lane = omp_get_thread_num() + 1
      worker_seen = worker_seen + 1
      fake_lane_time(lane) = real(10*lane, wp)
      call timer%start_id(shared_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) bad = bad + 1
      fake_lane_time(lane) = fake_lane_time(lane) + real(lane, wp)
      call timer%stop_id(shared_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) bad = bad + 1
!$omp end parallel

      if (worker_seen /= 2) error stop 1405
      if (bad /= 0) error stop 1406

      fake_lane_time(0) = 105.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1407)

      fake_lane_time(0) = 107.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1434)

      bad = 0
      warm_seen = 0

!$omp parallel num_threads(4) default(shared) private(ierr) reduction(+:bad, warm_seen)
      warm_seen = warm_seen + 1
      if (omp_get_thread_num() == 0) then
         fake_lane_time(1) = 24.0_wp
         call timer%start_id(warm_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) bad = bad + 1
         fake_lane_time(1) = 25.0_wp
         call timer%stop_id(warm_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) bad = bad + 1
      end if
!$omp end parallel

      if (bad /= 0) error stop 1436

      fake_lane_time(0) = 108.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1437)

      fake_lane_time(0) = 110.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1408)

      bad = 0
      solo_seen = 0
      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:bad, worker_seen, solo_seen)
      solo_seen = solo_seen + 1
      if (omp_get_thread_num() == 0) then
         worker_seen = worker_seen + 1
         fake_lane_time(1) = 30.0_wp
         call timer%start_id(solo_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) bad = bad + 1
         fake_lane_time(1) = 34.0_wp
         call timer%stop_id(solo_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) bad = bad + 1
         fake_lane_time(1) = 36.0_wp
         call timer%start_id(solo_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) bad = bad + 1
         fake_lane_time(1) = 40.0_wp
         call timer%stop_id(solo_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) bad = bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 1409
      if (solo_seen /= 2) error stop 1443
      if (bad /= 0) error stop 1410

      fake_lane_time(0) = 115.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1411)

      fake_lane_time(0) = 120.0_wp
      call timer%get_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1412)

      call expect_status(summary%num_entries, 3, 1413)
      call expect_status(summary%configured_lane_capacity, 5, 1414)
      call expect_status(summary%observed_participating_lane_count, 2, 1415)
      call expect_time(summary%timed_region_envelope_time, 11.0_wp, 1416)

      shared_idx = find_openmp_summary_entry(summary, "summary_shared", 0)
      if (shared_idx <= 0) error stop 1417
      solo_idx = find_openmp_summary_entry(summary, "summary_solo", 0)
      if (solo_idx <= 0) error stop 1418
      warm_idx = find_openmp_summary_entry(summary, "summary_warm", 0)
      if (warm_idx <= 0) error stop 1438

      call expect_status(summary%entries(shared_idx)%eligible_lane_count, 2, 1419)
      call expect_status(summary%entries(shared_idx)%participating_lane_count, 2, 1420)
      call expect_status(summary%entries(shared_idx)%missing_lane_count, 0, 1421)
      if (.not. summary%entries(shared_idx)%missing_lane_count_known) error stop 1445
      call expect_time(summary%entries(shared_idx)%sum_lane_inclusive_time, 3.0_wp, 1422)
      call expect_time(summary%entries(shared_idx)%avg_lane_inclusive_time, 1.5_wp, 1423)
      call expect_time(summary%entries(shared_idx)%max_lane_inclusive_time, 2.0_wp, 1424)
      call expect_time(summary%entries(shared_idx)%avg_lane_call_count, 1.0_wp, 1425)

      call expect_status(summary%entries(solo_idx)%eligible_lane_count, 2, 1426)
      call expect_status(summary%entries(solo_idx)%participating_lane_count, 1, 1427)
      call expect_status(summary%entries(solo_idx)%missing_lane_count, 1, 1428)
      if (.not. summary%entries(solo_idx)%missing_lane_count_known) error stop 1446
      call expect_time(summary%entries(solo_idx)%sum_lane_inclusive_time, 8.0_wp, 1429)
      call expect_time(summary%entries(solo_idx)%avg_lane_inclusive_time, 8.0_wp, 1430)
      call expect_time(summary%entries(solo_idx)%avg_lane_call_count, 2.0_wp, 1431)

      call expect_status(summary%entries(warm_idx)%eligible_lane_count, warm_seen, 1439)
      call expect_status(summary%entries(warm_idx)%participating_lane_count, 1, 1440)
      call expect_status(summary%entries(warm_idx)%missing_lane_count, warm_seen - 1, 1441)
      if (.not. summary%entries(warm_idx)%missing_lane_count_known) error stop 1447
      call expect_time(summary%entries(warm_idx)%sum_lane_inclusive_time, 1.0_wp, 1442)

      if (warm_seen <= solo_seen) then
         write (*, '(a)') "Skipping variable-team OpenMP cache regression subcase: runtime provided only two worker lanes"
      end if

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1432)
   end subroutine check_worker_team_size_summary_cache

   integer function find_openmp_summary_entry(summary, name, parent_id) result(idx)
      type(ftimer_openmp_summary_t), intent(in) :: summary
      character(len=*), intent(in) :: name
      integer, intent(in) :: parent_id
      integer :: i

      idx = 0
      do i = 1, summary%num_entries
         if (.not. allocated(summary%entries(i)%name)) cycle
         if ((summary%entries(i)%name == name) .and. (summary%entries(i)%parent_id == parent_id)) then
            idx = i
            return
         end if
      end do
   end function find_openmp_summary_entry
#endif

   function mock_openmp_clock() result(t)
      real(wp) :: t
      integer :: lane_id

#ifdef FTIMER_USE_OPENMP
      if (omp_in_parallel()) then
         lane_id = 1 + omp_get_thread_num()
      else
         lane_id = 0
      end if
#else
      lane_id = 0
#endif

      if ((lane_id < lbound(fake_lane_time, 1)) .or. (lane_id > ubound(fake_lane_time, 1))) then
         error stop "mock_openmp_clock lane id out of range"
      end if
      t = fake_lane_time(lane_id)
   end function mock_openmp_clock

end program ftimer_openmp_api_smoke
