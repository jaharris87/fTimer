program ftimer_openmp_summary_smoke
   use, intrinsic :: iso_fortran_env, only: int64
   use omp_lib, only: omp_get_thread_num, omp_in_parallel, omp_set_dynamic, omp_set_num_threads
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_parallel_region_t, &
                            ftimer_openmp_summary_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_IO, FTIMER_SUCCESS, ftimer_metadata_t, wp
   implicit none

   real(wp), save :: fake_lane_time(0:4) = 0.0_wp

   call omp_set_dynamic(.false.)
   call omp_set_num_threads(2)

   call check_openmp_summary_aggregates()
   call check_openmp_summary_active_refusal()
   call check_openmp_summary_serial_active_refusal()
   call check_openmp_summary_mixed_epochs()
   call check_openmp_summary_self_time_boundaries()
   call check_openmp_summary_csv_append_validation()
   call check_openmp_summary_no_ierr_worker_diagnostics()

contains

   subroutine check_openmp_summary_aggregates()
      character(len=*), parameter :: report_path = 'openmp_summary_report.txt'
      character(len=*), parameter :: csv_path = 'openmp_summary.csv'
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_summary_t) :: summary
      type(ftimer_openmp_t) :: timer
      type(ftimer_metadata_t) :: metadata(1)
      character(len=:), allocatable :: csv_text
      character(len=:), allocatable :: report_text
      integer :: child_idx
      integer :: child_id
      integer :: ierr
      integer :: root_idx
      integer :: root_id
      integer :: serial_idx
      integer :: serial_id
      integer :: sparse_idx
      integer :: sparse_id
      integer :: worker_bad
      integer :: worker_seen

      call delete_if_exists(report_path)
      call delete_if_exists(csv_path)

      config%max_lanes = 5
      config%max_worker_diagnostics = 4

      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1)
      fake_lane_time(0) = 100.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2)

      call timer%register_timer("root", root_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 3)
      call timer%register_timer("child", child_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 4)
      call timer%register_timer("serial", serial_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 5)
      call timer%register_timer("sparse", sparse_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 6)

      fake_lane_time(0) = 101.0_wp
      call timer%start_id(serial_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 7)
      fake_lane_time(0) = 103.0_wp
      call timer%stop_id(serial_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 8)

      fake_lane_time(0) = 110.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 9)

      worker_bad = 0
      worker_seen = 0
!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      worker_seen = worker_seen + 1
      if (omp_get_thread_num() == 0) then
         fake_lane_time(1) = 10.0_wp
         call timer%start_id(root_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(1) = 12.0_wp
         call timer%start_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(1) = 15.0_wp
         call timer%stop_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(1) = 20.0_wp
         call timer%stop_id(root_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      else
         fake_lane_time(2) = 30.0_wp
         call timer%start_id(root_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 42.0_wp
         call timer%stop_id(root_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1

         fake_lane_time(2) = 45.0_wp
         call timer%start_id(sparse_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(2) = 50.0_wp
         call timer%stop_id(sparse_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_seen /= 2) error stop 10
      if (worker_bad /= 0) error stop 11

      fake_lane_time(0) = 116.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 12)

      fake_lane_time(0) = 121.0_wp
      call timer%get_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 13)

      call expect_int(summary%num_entries, 4, 14)
      call expect_int(summary%configured_lane_capacity, 5, 15)
      call expect_int(summary%observed_participating_lane_count, 3, 16)
      call expect_time(summary%summary_window_time, 21.0_wp, 17)
      call expect_time(summary%timed_region_envelope_time, 6.0_wp, 18)
      call expect_time(summary%sum_lane_root_inclusive_time, 29.0_wp, 19)
      call expect_time(summary%sum_lane_self_time, 29.0_wp, 20)

      root_idx = find_entry(summary, "root", 0)
      if (root_idx <= 0) error stop 21
      child_idx = find_entry(summary, "child", summary%entries(root_idx)%node_id)
      if (child_idx <= 0) error stop 22
      serial_idx = find_entry(summary, "serial", 0)
      if (serial_idx <= 0) error stop 23
      sparse_idx = find_entry(summary, "sparse", 0)
      if (sparse_idx <= 0) error stop 24

      call expect_entry(summary, root_idx, eligible=2, participating=2, missing=0, &
                        sum_inclusive=22.0_wp, sum_self=19.0_wp, &
                        min_inclusive=10.0_wp, avg_inclusive=11.0_wp, max_inclusive=12.0_wp, &
                        inclusive_imbalance=12.0_wp/11.0_wp, min_self=7.0_wp, avg_self=9.5_wp, &
                        max_self=12.0_wp, self_imbalance=12.0_wp/9.5_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=25)
      call expect_entry(summary, child_idx, eligible=2, participating=1, missing=1, &
                        sum_inclusive=3.0_wp, sum_self=3.0_wp, &
                        min_inclusive=3.0_wp, avg_inclusive=3.0_wp, max_inclusive=3.0_wp, &
                        inclusive_imbalance=1.0_wp, min_self=3.0_wp, avg_self=3.0_wp, &
                        max_self=3.0_wp, self_imbalance=1.0_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=26)
      call expect_entry(summary, serial_idx, eligible=1, participating=1, missing=0, &
                        sum_inclusive=2.0_wp, sum_self=2.0_wp, &
                        min_inclusive=2.0_wp, avg_inclusive=2.0_wp, max_inclusive=2.0_wp, &
                        inclusive_imbalance=1.0_wp, min_self=2.0_wp, avg_self=2.0_wp, &
                        max_self=2.0_wp, self_imbalance=1.0_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=27)
      call expect_entry(summary, sparse_idx, eligible=2, participating=1, missing=1, &
                        sum_inclusive=5.0_wp, sum_self=5.0_wp, &
                        min_inclusive=5.0_wp, avg_inclusive=5.0_wp, max_inclusive=5.0_wp, &
                        inclusive_imbalance=1.0_wp, min_self=5.0_wp, avg_self=5.0_wp, &
                        max_self=5.0_wp, self_imbalance=1.0_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=28)

      metadata(1)%key = 'Case'
      metadata(1)%value = 'openmp summary'
      call timer%write_openmp_summary(report_path, metadata=metadata, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 29)
      report_text = read_file_text(report_path)
      call expect_contains(report_text, 'OpenMP summary', 30)
      call expect_contains(report_text, 'Timed region envelope time (s) : 6.000000', 31)
      call expect_contains(report_text, 'Summed lane root work (s)      : 29.000000', 32)
      call expect_contains(report_text, 'root', 33)
      call expect_contains(report_text, '22.000000', 34)
      call expect_contains(report_text, 'Missing', 35)
      call expect_report_entry(report_text, 'root', part=2, missing=0, &
                               sum_inclusive=22.0_wp, sum_self=19.0_wp, &
                               min_inclusive=10.0_wp, avg_inclusive=11.0_wp, max_inclusive=12.0_wp, &
                               avg_self=9.5_wp, min_calls=1_int64, avg_calls=1.0_wp, max_calls=1_int64, &
                               stop_code=74)
      call expect_report_entry(report_text, 'child', part=1, missing=1, &
                               sum_inclusive=3.0_wp, sum_self=3.0_wp, &
                               min_inclusive=3.0_wp, avg_inclusive=3.0_wp, max_inclusive=3.0_wp, &
                               avg_self=3.0_wp, min_calls=1_int64, avg_calls=1.0_wp, max_calls=1_int64, &
                               stop_code=75)
      call expect_report_entry(report_text, 'serial', part=1, missing=0, &
                               sum_inclusive=2.0_wp, sum_self=2.0_wp, &
                               min_inclusive=2.0_wp, avg_inclusive=2.0_wp, max_inclusive=2.0_wp, &
                               avg_self=2.0_wp, min_calls=1_int64, avg_calls=1.0_wp, max_calls=1_int64, &
                               stop_code=76)
      call expect_report_entry(report_text, 'sparse', part=1, missing=1, &
                               sum_inclusive=5.0_wp, sum_self=5.0_wp, &
                               min_inclusive=5.0_wp, avg_inclusive=5.0_wp, max_inclusive=5.0_wp, &
                               avg_self=5.0_wp, min_calls=1_int64, avg_calls=1.0_wp, max_calls=1_int64, &
                               stop_code=77)

      call timer%write_openmp_summary_csv(csv_path, metadata=metadata, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 36)
      csv_text = read_file_text(csv_path)
      call expect_contains(csv_text, 'summary_kind', 37)
      call expect_contains(csv_text, 'timed_region_envelope_time', 38)
      call expect_contains(csv_text, 'sum_lane_root_inclusive_time', 39)
      call expect_contains(csv_text, 'eligible_lane_count', 40)
      call expect_contains(csv_text, 'missing_lane_count_known', 41)
      call expect_contains(csv_text, '"1","openmp","summary"', 42)
      call expect_contains(csv_text, '"1","openmp","metadata","Case","openmp summary"', 43)
      call expect_contains(csv_text, '"1","openmp","entry"', 44)
      call expect_contains(csv_text, '"root"', 45)
      call expect_contains(csv_text, '"child"', 46)
      call expect_csv_summary_field(csv_text, 'summary_window_time', csv_real_text(21.0_wp), 48)
      call expect_csv_summary_field(csv_text, 'timed_region_envelope_time', csv_real_text(6.0_wp), 49)
      call expect_csv_summary_field(csv_text, 'sum_lane_root_inclusive_time', csv_real_text(29.0_wp), 50)
      call expect_csv_summary_field(csv_text, 'sum_lane_self_time', csv_real_text(29.0_wp), 51)
      call expect_csv_metadata_field(csv_text, 'Case', 'value', 'openmp summary', 52)
      call expect_csv_entry_field(csv_text, 'root', 'eligible_lane_count', '2', 53)
      call expect_csv_entry_field(csv_text, 'root', 'participating_lane_count', '2', 54)
      call expect_csv_entry_field(csv_text, 'root', 'missing_lane_count', '0', 55)
      call expect_csv_entry_field(csv_text, 'root', 'sum_lane_inclusive_time', csv_real_text(22.0_wp), 56)
      call expect_csv_entry_field(csv_text, 'root', 'sum_lane_self_time', csv_real_text(19.0_wp), 57)
      call expect_csv_entry_field(csv_text, 'root', 'min_lane_inclusive_time', csv_real_text(10.0_wp), 58)
      call expect_csv_entry_field(csv_text, 'root', 'avg_lane_inclusive_time', csv_real_text(11.0_wp), 59)
      call expect_csv_entry_field(csv_text, 'root', 'max_lane_inclusive_time', csv_real_text(12.0_wp), 60)
      call expect_csv_entry_field(csv_text, 'root', 'lane_inclusive_imbalance', csv_real_text(12.0_wp/11.0_wp), 61)
      call expect_csv_entry_field(csv_text, 'root', 'min_lane_self_time', csv_real_text(7.0_wp), 62)
      call expect_csv_entry_field(csv_text, 'root', 'avg_lane_self_time', csv_real_text(9.5_wp), 63)
      call expect_csv_entry_field(csv_text, 'root', 'max_lane_self_time', csv_real_text(12.0_wp), 64)
      call expect_csv_entry_field(csv_text, 'root', 'lane_self_imbalance', csv_real_text(12.0_wp/9.5_wp), 65)
      call expect_csv_entry_field(csv_text, 'root', 'min_lane_call_count', '1', 66)
      call expect_csv_entry_field(csv_text, 'root', 'avg_lane_call_count', csv_real_text(1.0_wp), 67)
      call expect_csv_entry_field(csv_text, 'root', 'max_lane_call_count', '1', 68)
      call expect_csv_entry_field(csv_text, 'child', 'eligible_lane_count', '2', 69)
      call expect_csv_entry_field(csv_text, 'child', 'participating_lane_count', '1', 70)
      call expect_csv_entry_field(csv_text, 'child', 'missing_lane_count', '1', 71)
      call expect_csv_entry_field(csv_text, 'child', 'sum_lane_self_time', csv_real_text(3.0_wp), 72)
      call expect_csv_entry_field(csv_text, 'child', 'lane_inclusive_imbalance', csv_real_text(1.0_wp), 73)
      call expect_csv_entry_field(csv_text, 'child', 'min_lane_self_time', csv_real_text(3.0_wp), 74)
      call expect_csv_entry_field(csv_text, 'child', 'avg_lane_self_time', csv_real_text(3.0_wp), 75)
      call expect_csv_entry_field(csv_text, 'child', 'max_lane_self_time', csv_real_text(3.0_wp), 76)
      call expect_csv_entry_field(csv_text, 'child', 'lane_self_imbalance', csv_real_text(1.0_wp), 77)
      call expect_csv_entry_field(csv_text, 'serial', 'eligible_lane_count', '1', 78)
      call expect_csv_entry_field(csv_text, 'serial', 'sum_lane_inclusive_time', csv_real_text(2.0_wp), 79)
      call expect_csv_entry_field(csv_text, 'serial', 'min_lane_self_time', csv_real_text(2.0_wp), 80)
      call expect_csv_entry_field(csv_text, 'serial', 'avg_lane_self_time', csv_real_text(2.0_wp), 81)
      call expect_csv_entry_field(csv_text, 'serial', 'max_lane_self_time', csv_real_text(2.0_wp), 82)
      call expect_csv_entry_field(csv_text, 'serial', 'lane_self_imbalance', csv_real_text(1.0_wp), 83)
      call expect_csv_entry_field(csv_text, 'sparse', 'eligible_lane_count', '2', 84)
      call expect_csv_entry_field(csv_text, 'sparse', 'participating_lane_count', '1', 85)
      call expect_csv_entry_field(csv_text, 'sparse', 'missing_lane_count', '1', 86)
      call expect_csv_entry_field(csv_text, 'sparse', 'lane_inclusive_imbalance', csv_real_text(1.0_wp), 87)
      call expect_csv_entry_field(csv_text, 'sparse', 'min_lane_self_time', csv_real_text(5.0_wp), 88)
      call expect_csv_entry_field(csv_text, 'sparse', 'avg_lane_self_time', csv_real_text(5.0_wp), 89)
      call expect_csv_entry_field(csv_text, 'sparse', 'max_lane_self_time', csv_real_text(5.0_wp), 90)
      call expect_csv_entry_field(csv_text, 'sparse', 'lane_self_imbalance', csv_real_text(1.0_wp), 91)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 92)
      call delete_if_exists(report_path)
      call delete_if_exists(csv_path)
   end subroutine check_openmp_summary_aggregates

   subroutine check_openmp_summary_active_refusal()
      character(len=*), parameter :: csv_path = 'openmp_summary_active.csv'
      character(len=*), parameter :: report_path = 'openmp_summary_active.txt'
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_summary_t) :: summary
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: timer_id
      integer :: worker_bad
      logical :: exists

      call delete_if_exists(report_path)
      call delete_if_exists(csv_path)

      config%max_lanes = 3
      config%max_worker_diagnostics = 4
      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 60)
      fake_lane_time(0) = 200.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 61)
      call timer%register_timer("active", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 62)

      fake_lane_time(0) = 201.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 63)

      worker_bad = 0
!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad)
      if (omp_get_thread_num() == 1) then
         fake_lane_time(2) = 10.0_wp
         call timer%start_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_bad /= 0) error stop 64

      fake_lane_time(0) = 203.0_wp
      call timer%get_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 65)
      call expect_int(summary%num_entries, 0, 66)

      call timer%write_openmp_summary(report_path, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 67)
      inquire (file=report_path, exist=exists)
      if (exists) error stop 68

      call timer%write_openmp_summary_csv(csv_path, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 69)
      inquire (file=csv_path, exist=exists)
      if (exists) error stop 70

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad)
      if (omp_get_thread_num() == 1) then
         fake_lane_time(2) = 14.0_wp
         call timer%stop_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel

      if (worker_bad /= 0) error stop 71
      fake_lane_time(0) = 205.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 72)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 73)
   end subroutine check_openmp_summary_active_refusal

   subroutine check_openmp_summary_serial_active_refusal()
      character(len=*), parameter :: csv_path = 'openmp_summary_serial_active.csv'
      character(len=*), parameter :: csv_sentinel = 'csv sentinel'
      character(len=*), parameter :: report_path = 'openmp_summary_serial_active.txt'
      character(len=*), parameter :: report_sentinel = 'report sentinel'
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_summary_t) :: summary
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: timer_id

      call delete_if_exists(report_path)
      call delete_if_exists(csv_path)

      config%max_lanes = 2
      config%max_worker_diagnostics = 4
      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 100)
      fake_lane_time(0) = 300.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 101)
      call timer%register_timer("serial_active", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 102)

      fake_lane_time(0) = 301.0_wp
      call timer%start_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 103)
      call write_text_file(report_path, report_sentinel//new_line('a'))
      call write_text_file(csv_path, csv_sentinel//new_line('a'))

      call timer%get_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 104)
      call expect_int(summary%num_entries, 0, 105)

      call timer%write_openmp_summary(report_path, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 106)
      call expect_equal_text(read_file_text(report_path), report_sentinel//new_line('a'), 107)

      call timer%write_openmp_summary_csv(csv_path, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 108)
      call expect_equal_text(read_file_text(csv_path), csv_sentinel//new_line('a'), 109)

      fake_lane_time(0) = 305.0_wp
      call timer%stop_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 110)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 111)
      call delete_if_exists(report_path)
      call delete_if_exists(csv_path)
   end subroutine check_openmp_summary_serial_active_refusal

   subroutine check_openmp_summary_mixed_epochs()
      character(len=*), parameter :: csv_path = 'openmp_summary_mixed_epochs.csv'
      character(len=*), parameter :: report_path = 'openmp_summary_mixed_epochs.txt'
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_summary_t) :: summary
      type(ftimer_openmp_t) :: timer
      character(len=:), allocatable :: csv_text
      character(len=:), allocatable :: report_text
      integer :: expected_eligible
      integer :: ierr
      integer :: mixed_id
      integer :: mixed_idx
      integer :: worker_bad
      integer :: worker_seen

      call delete_if_exists(report_path)
      call delete_if_exists(csv_path)

      config%max_lanes = 5
      config%max_worker_diagnostics = 4
      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 120)
      fake_lane_time(0) = 400.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 121)
      call timer%register_timer("mixed", mixed_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 122)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 123)
      worker_bad = 0
      worker_seen = 0
!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      worker_seen = worker_seen + 1
      if (omp_get_thread_num() == 0) then
         fake_lane_time(1) = 10.0_wp
         call timer%start_id(mixed_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(1) = 12.0_wp
         call timer%stop_id(mixed_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel
      if (worker_seen /= 2) error stop 124
      if (worker_bad /= 0) error stop 125
      fake_lane_time(0) = 405.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 126)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 127)
      worker_bad = 0
      worker_seen = 0
!$omp parallel num_threads(4) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
      worker_seen = worker_seen + 1
      if (omp_get_thread_num() == 0) then
         fake_lane_time(1) = 20.0_wp
         call timer%start_id(mixed_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
         fake_lane_time(1) = 24.0_wp
         call timer%stop_id(mixed_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
      end if
!$omp end parallel
      if (worker_seen < 2) error stop 128
      if (worker_bad /= 0) error stop 129
      expected_eligible = max(2, worker_seen)
      fake_lane_time(0) = 411.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 130)

      fake_lane_time(0) = 415.0_wp
      call timer%get_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 131)
      mixed_idx = find_entry(summary, "mixed", 0)
      if (mixed_idx <= 0) error stop 132
      ! Mixed epochs retain the union/maximum eligible lane set while marking
      ! missing-lane precision unknown.
      call expect_int(summary%entries(mixed_idx)%eligible_lane_count, expected_eligible, 133)
      call expect_int(summary%entries(mixed_idx)%participating_lane_count, 1, 134)
      call expect_int(summary%entries(mixed_idx)%missing_lane_count, expected_eligible - 1, 135)
      if (summary%entries(mixed_idx)%missing_lane_count_known) error stop 136
      call expect_time(summary%entries(mixed_idx)%sum_lane_inclusive_time, 6.0_wp, 137)
      call expect_time(summary%entries(mixed_idx)%sum_lane_self_time, 6.0_wp, 138)
      call expect_int64(summary%entries(mixed_idx)%max_lane_call_count, 2_int64, 139)

      call timer%write_openmp_summary(report_path, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 140)
      report_text = read_file_text(report_path)
      call expect_report_entry_missing_text(report_text, 'mixed', 'unknown', 141)

      call timer%write_openmp_summary_csv(csv_path, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 142)
      csv_text = read_file_text(csv_path)
      call expect_csv_entry_field(csv_text, 'mixed', 'eligible_lane_count', &
                                  csv_int_text(expected_eligible), 143)
      call expect_csv_entry_field(csv_text, 'mixed', 'missing_lane_count_known', 'false', 144)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 145)
      call delete_if_exists(report_path)
      call delete_if_exists(csv_path)
   end subroutine check_openmp_summary_mixed_epochs

   subroutine check_openmp_summary_self_time_boundaries()
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_summary_t) :: summary
      type(ftimer_openmp_t) :: timer
      integer :: child_id
      integer :: child_idx
      integer :: grandchild_id
      integer :: grandchild_idx
      integer :: ierr
      integer :: root_id
      integer :: root_idx
      integer :: sibling_id
      integer :: sibling_idx

      config%max_lanes = 1
      config%max_worker_diagnostics = 4
      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 150)
      fake_lane_time(0) = 500.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 151)
      call timer%register_timer("tree_root", root_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 152)
      call timer%register_timer("tree_child", child_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 153)
      call timer%register_timer("tree_grandchild", grandchild_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 154)
      call timer%register_timer("tree_sibling", sibling_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 155)

      fake_lane_time(0) = 0.0_wp
      call timer%start_id(root_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 156)
      fake_lane_time(0) = 1.0_wp
      call timer%start_id(child_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 157)
      fake_lane_time(0) = 2.0_wp
      call timer%start_id(grandchild_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 158)
      fake_lane_time(0) = 4.0_wp
      call timer%stop_id(grandchild_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 159)
      fake_lane_time(0) = 6.0_wp
      call timer%stop_id(child_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 160)
      fake_lane_time(0) = 7.0_wp
      call timer%start_id(sibling_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 161)
      fake_lane_time(0) = 9.0_wp
      call timer%stop_id(sibling_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 162)
      fake_lane_time(0) = 10.0_wp
      call timer%stop_id(root_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 163)

      call timer%get_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 164)
      root_idx = find_entry(summary, "tree_root", 0)
      if (root_idx <= 0) error stop 165
      child_idx = find_entry(summary, "tree_child", summary%entries(root_idx)%node_id)
      if (child_idx <= 0) error stop 166
      grandchild_idx = find_entry(summary, "tree_grandchild", summary%entries(child_idx)%node_id)
      if (grandchild_idx <= 0) error stop 167
      sibling_idx = find_entry(summary, "tree_sibling", summary%entries(root_idx)%node_id)
      if (sibling_idx <= 0) error stop 168

      call expect_entry(summary, root_idx, eligible=1, participating=1, missing=0, &
                        sum_inclusive=10.0_wp, sum_self=3.0_wp, &
                        min_inclusive=10.0_wp, avg_inclusive=10.0_wp, max_inclusive=10.0_wp, &
                        inclusive_imbalance=1.0_wp, min_self=3.0_wp, avg_self=3.0_wp, &
                        max_self=3.0_wp, self_imbalance=1.0_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=169)
      call expect_entry(summary, child_idx, eligible=1, participating=1, missing=0, &
                        sum_inclusive=5.0_wp, sum_self=3.0_wp, &
                        min_inclusive=5.0_wp, avg_inclusive=5.0_wp, max_inclusive=5.0_wp, &
                        inclusive_imbalance=1.0_wp, min_self=3.0_wp, avg_self=3.0_wp, &
                        max_self=3.0_wp, self_imbalance=1.0_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=170)
      call expect_entry(summary, grandchild_idx, eligible=1, participating=1, missing=0, &
                        sum_inclusive=2.0_wp, sum_self=2.0_wp, &
                        min_inclusive=2.0_wp, avg_inclusive=2.0_wp, max_inclusive=2.0_wp, &
                        inclusive_imbalance=1.0_wp, min_self=2.0_wp, avg_self=2.0_wp, &
                        max_self=2.0_wp, self_imbalance=1.0_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=171)
      call expect_entry(summary, sibling_idx, eligible=1, participating=1, missing=0, &
                        sum_inclusive=2.0_wp, sum_self=2.0_wp, &
                        min_inclusive=2.0_wp, avg_inclusive=2.0_wp, max_inclusive=2.0_wp, &
                        inclusive_imbalance=1.0_wp, min_self=2.0_wp, avg_self=2.0_wp, &
                        max_self=2.0_wp, self_imbalance=1.0_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=172)
      call expect_time(summary%sum_lane_self_time, 10.0_wp, 173)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 174)
   end subroutine check_openmp_summary_self_time_boundaries

   subroutine check_openmp_summary_csv_append_validation()
      character(len=*), parameter :: bad_csv_path = 'openmp_summary_bad_append.csv'
      character(len=*), parameter :: csv_path = 'openmp_summary_append.csv'
      character(len=*), parameter :: truncated_csv_path = 'openmp_summary_truncated_append.csv'
      character(len=*), parameter :: wrong_header_csv_path = 'openmp_summary_wrong_header_append.csv'
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer
      character(len=:), allocatable :: bad_text
      character(len=:), allocatable :: csv_text
      character(len=:), allocatable :: header
      integer :: ierr
      integer :: timer_id

      call delete_if_exists(csv_path)
      call delete_if_exists(bad_csv_path)
      call delete_if_exists(truncated_csv_path)
      call delete_if_exists(wrong_header_csv_path)

      config%max_lanes = 1
      config%max_worker_diagnostics = 4
      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 180)
      fake_lane_time(0) = 600.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 181)
      call timer%register_timer("append", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 182)
      call timer%start_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 183)
      fake_lane_time(0) = 602.0_wp
      call timer%stop_id(timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 184)

      call timer%write_openmp_summary_csv(csv_path, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 185)
      csv_text = read_file_text(csv_path)
      header = first_line(csv_text)
      call timer%write_openmp_summary_csv(csv_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 186)
      csv_text = read_file_text(csv_path)
      call expect_int(count_occurrences(csv_text, header), 1, 187)

      bad_text = header//new_line('a')//'"1","openmp","summary"'//new_line('a')
      call write_text_file(bad_csv_path, bad_text)
      call timer%write_openmp_summary_csv(bad_csv_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 188)
      call expect_equal_text(read_file_text(bad_csv_path), bad_text, 189)

      bad_text = header//new_line('a')//'"1","openmp","summary",'
      call write_text_file(truncated_csv_path, bad_text)
      call timer%write_openmp_summary_csv(truncated_csv_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 190)
      call expect_equal_text(read_file_text(truncated_csv_path), bad_text, 191)

      bad_text = 'format_version,summary_kind,record_type'//new_line('a')
      call write_text_file(wrong_header_csv_path, bad_text)
      call timer%write_openmp_summary_csv(wrong_header_csv_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 193)
      call expect_equal_text(read_file_text(wrong_header_csv_path), bad_text, 194)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 195)
      call delete_if_exists(csv_path)
      call delete_if_exists(bad_csv_path)
      call delete_if_exists(truncated_csv_path)
      call delete_if_exists(wrong_header_csv_path)
   end subroutine check_openmp_summary_csv_append_validation

   subroutine check_openmp_summary_no_ierr_worker_diagnostics()
      character(len=*), parameter :: csv_path = 'openmp_summary_no_ierr_diag.csv'
      character(len=*), parameter :: report_path = 'openmp_summary_no_ierr_diag.txt'
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer
      character(len=:), allocatable :: csv_text
      character(len=:), allocatable :: report_text
      integer :: ierr
      integer :: timer_id
      integer :: worker_seen
      logical :: exists

      call delete_if_exists(report_path)
      call delete_if_exists(csv_path)

      config%max_lanes = 3
      config%max_worker_diagnostics = 4
      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 200)
      fake_lane_time(0) = 700.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 201)
      call timer%register_timer("diag", timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 202)

      worker_seen = 0
!$omp parallel num_threads(2) default(shared) reduction(+:worker_seen)
      worker_seen = worker_seen + 1
      if (omp_get_thread_num() == 1) call timer%start_id(timer_id)
!$omp end parallel
      if (worker_seen /= 2) error stop 203

      call timer%write_openmp_summary(report_path)
      inquire (file=report_path, exist=exists)
      if (.not. exists) error stop 204
      report_text = read_file_text(report_path)
      call expect_contains(report_text, 'OpenMP summary', 205)

      worker_seen = 0
!$omp parallel num_threads(2) default(shared) reduction(+:worker_seen)
      worker_seen = worker_seen + 1
      if (omp_get_thread_num() == 1) call timer%start_id(timer_id)
!$omp end parallel
      if (worker_seen /= 2) error stop 206

      call timer%write_openmp_summary_csv(csv_path)
      inquire (file=csv_path, exist=exists)
      if (.not. exists) error stop 207
      csv_text = read_file_text(csv_path)
      call expect_csv_summary_field(csv_text, 'num_entries', '0', 208)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 209)
      call delete_if_exists(report_path)
      call delete_if_exists(csv_path)
   end subroutine check_openmp_summary_no_ierr_worker_diagnostics

   subroutine expect_entry(summary, idx, eligible, participating, missing, sum_inclusive, sum_self, &
                           min_inclusive, avg_inclusive, max_inclusive, inclusive_imbalance, &
                           min_self, avg_self, max_self, self_imbalance, min_calls, avg_calls, &
                           max_calls, stop_code)
      type(ftimer_openmp_summary_t), intent(in) :: summary
      integer, intent(in) :: idx
      integer, intent(in) :: eligible
      integer, intent(in) :: participating
      integer, intent(in) :: missing
      real(wp), intent(in) :: sum_inclusive
      real(wp), intent(in) :: sum_self
      real(wp), intent(in) :: min_inclusive
      real(wp), intent(in) :: avg_inclusive
      real(wp), intent(in) :: max_inclusive
      real(wp), intent(in) :: inclusive_imbalance
      real(wp), intent(in) :: min_self
      real(wp), intent(in) :: avg_self
      real(wp), intent(in) :: max_self
      real(wp), intent(in) :: self_imbalance
      integer(int64), intent(in) :: min_calls
      real(wp), intent(in) :: avg_calls
      integer(int64), intent(in) :: max_calls
      integer, intent(in) :: stop_code

      call expect_int(summary%entries(idx)%eligible_lane_count, eligible, stop_code)
      call expect_int(summary%entries(idx)%participating_lane_count, participating, stop_code + 100)
      call expect_int(summary%entries(idx)%missing_lane_count, missing, stop_code + 200)
      if (.not. summary%entries(idx)%missing_lane_count_known) error stop stop_code + 300
      call expect_time(summary%entries(idx)%sum_lane_inclusive_time, sum_inclusive, stop_code + 400)
      call expect_time(summary%entries(idx)%sum_lane_self_time, sum_self, stop_code + 500)
      call expect_time(summary%entries(idx)%min_lane_inclusive_time, min_inclusive, stop_code + 600)
      call expect_time(summary%entries(idx)%avg_lane_inclusive_time, avg_inclusive, stop_code + 700)
      call expect_time(summary%entries(idx)%max_lane_inclusive_time, max_inclusive, stop_code + 800)
      call expect_time(summary%entries(idx)%lane_inclusive_imbalance, inclusive_imbalance, stop_code + 900)
      call expect_time(summary%entries(idx)%min_lane_self_time, min_self, stop_code + 1000)
      call expect_time(summary%entries(idx)%avg_lane_self_time, avg_self, stop_code + 1100)
      call expect_time(summary%entries(idx)%max_lane_self_time, max_self, stop_code + 1200)
      call expect_time(summary%entries(idx)%lane_self_imbalance, self_imbalance, stop_code + 1300)
      call expect_int64(summary%entries(idx)%min_lane_call_count, min_calls, stop_code + 1400)
      call expect_time(summary%entries(idx)%avg_lane_call_count, avg_calls, stop_code + 1500)
      call expect_int64(summary%entries(idx)%max_lane_call_count, max_calls, stop_code + 1600)
   end subroutine expect_entry

   integer function find_entry(summary, name, parent_id) result(idx)
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
   end function find_entry

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

   subroutine expect_int64(actual, expected, stop_code)
      integer(int64), intent(in) :: actual
      integer(int64), intent(in) :: expected
      integer, intent(in) :: stop_code

      if (actual /= expected) error stop stop_code
   end subroutine expect_int64

   subroutine expect_time(actual, expected, stop_code)
      real(wp), intent(in) :: actual
      real(wp), intent(in) :: expected
      integer, intent(in) :: stop_code

      if (abs(actual - expected) > 1.0e-12_wp) error stop stop_code
   end subroutine expect_time

   subroutine expect_contains(text, needle, stop_code)
      character(len=*), intent(in) :: text
      character(len=*), intent(in) :: needle
      integer, intent(in) :: stop_code

      if (index(text, needle) <= 0) error stop stop_code
   end subroutine expect_contains

   subroutine expect_report_entry(report_text, name, part, missing, sum_inclusive, sum_self, &
                                  min_inclusive, avg_inclusive, max_inclusive, avg_self, &
                                  min_calls, avg_calls, max_calls, stop_code)
      character(len=*), intent(in) :: report_text
      character(len=*), intent(in) :: name
      integer, intent(in) :: part
      integer, intent(in) :: missing
      real(wp), intent(in) :: sum_inclusive
      real(wp), intent(in) :: sum_self
      real(wp), intent(in) :: min_inclusive
      real(wp), intent(in) :: avg_inclusive
      real(wp), intent(in) :: max_inclusive
      real(wp), intent(in) :: avg_self
      integer(int64), intent(in) :: min_calls
      real(wp), intent(in) :: avg_calls
      integer(int64), intent(in) :: max_calls
      integer, intent(in) :: stop_code
      character(len=:), allocatable :: row
      character(len=128) :: parsed_name
      integer :: io
      integer :: parsed_missing
      integer :: parsed_part
      integer(int64) :: parsed_max_calls
      integer(int64) :: parsed_min_calls
      real(wp) :: parsed_avg_calls
      real(wp) :: parsed_avg_inclusive
      real(wp) :: parsed_avg_self
      real(wp) :: parsed_max_inclusive
      real(wp) :: parsed_min_inclusive
      real(wp) :: parsed_sum_inclusive
      real(wp) :: parsed_sum_self

      row = find_report_row(report_text, name)
      if (len(row) <= 0) error stop stop_code
      read (row, *, iostat=io) parsed_name, parsed_part, parsed_missing, &
         parsed_sum_inclusive, parsed_sum_self, parsed_min_inclusive, parsed_avg_inclusive, &
         parsed_max_inclusive, parsed_avg_self, parsed_min_calls, parsed_avg_calls, parsed_max_calls
      if (io /= 0) error stop stop_code + 1000
      if (trim(parsed_name) /= name) error stop stop_code + 1100
      call expect_int(parsed_part, part, stop_code + 1200)
      call expect_int(parsed_missing, missing, stop_code + 1300)
      call expect_time(parsed_sum_inclusive, sum_inclusive, stop_code + 1400)
      call expect_time(parsed_sum_self, sum_self, stop_code + 1500)
      call expect_time(parsed_min_inclusive, min_inclusive, stop_code + 1600)
      call expect_time(parsed_avg_inclusive, avg_inclusive, stop_code + 1700)
      call expect_time(parsed_max_inclusive, max_inclusive, stop_code + 1800)
      call expect_time(parsed_avg_self, avg_self, stop_code + 1900)
      call expect_int64(parsed_min_calls, min_calls, stop_code + 2000)
      call expect_time(parsed_avg_calls, avg_calls, stop_code + 2100)
      call expect_int64(parsed_max_calls, max_calls, stop_code + 2200)
   end subroutine expect_report_entry

   subroutine expect_report_entry_missing_text(report_text, name, expected, stop_code)
      character(len=*), intent(in) :: report_text
      character(len=*), intent(in) :: name
      character(len=*), intent(in) :: expected
      integer, intent(in) :: stop_code
      character(len=:), allocatable :: row
      character(len=128) :: parsed_missing
      character(len=128) :: parsed_name
      integer :: io
      integer :: parsed_part

      row = find_report_row(report_text, name)
      if (len(row) <= 0) error stop stop_code
      read (row, *, iostat=io) parsed_name, parsed_part, parsed_missing
      if (io /= 0) error stop stop_code + 1000
      if (trim(parsed_name) /= name) error stop stop_code + 1100
      if (trim(parsed_missing) /= expected) error stop stop_code + 1200
   end subroutine expect_report_entry_missing_text

   function find_report_row(report_text, name) result(row)
      character(len=*), intent(in) :: report_text
      character(len=*), intent(in) :: name
      character(len=:), allocatable :: row
      character(len=:), allocatable :: candidate
      integer :: line_end
      integer :: line_start
      integer :: newline_pos

      row = ''
      line_start = 1
      do while (line_start <= len(report_text))
         newline_pos = index(report_text(line_start:), new_line('a'))
         if (newline_pos <= 0) then
            line_end = len(report_text)
         else
            line_end = line_start + newline_pos - 2
         end if
         if (line_end >= line_start) then
            candidate = report_text(line_start:line_end)
            if (first_token(candidate) == name) then
               row = candidate
               return
            end if
         end if
         if (newline_pos <= 0) exit
         line_start = line_end + 2
      end do
   end function find_report_row

   function first_token(line) result(token)
      character(len=*), intent(in) :: line
      character(len=:), allocatable :: token
      integer :: i
      integer :: start

      token = ''
      start = 0
      do i = 1, len_trim(line)
         if (line(i:i) /= ' ') then
            start = i
            exit
         end if
      end do
      if (start <= 0) return
      do i = start, len_trim(line)
         if (line(i:i) == ' ') then
            token = line(start:i - 1)
            return
         end if
      end do
      token = line(start:len_trim(line))
   end function first_token

   subroutine expect_equal_text(actual, expected, stop_code)
      character(len=*), intent(in) :: actual
      character(len=*), intent(in) :: expected
      integer, intent(in) :: stop_code

      if ((len(actual) /= len(expected)) .or. (actual /= expected)) error stop stop_code
   end subroutine expect_equal_text

   subroutine expect_csv_summary_field(csv_text, column, expected, stop_code)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: column
      character(len=*), intent(in) :: expected
      integer, intent(in) :: stop_code

      call expect_csv_record_field(csv_text, 'summary', '', column, expected, stop_code)
   end subroutine expect_csv_summary_field

   subroutine expect_csv_metadata_field(csv_text, key, column, expected, stop_code)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: key
      character(len=*), intent(in) :: column
      character(len=*), intent(in) :: expected
      integer, intent(in) :: stop_code

      call expect_csv_record_field(csv_text, 'metadata', key, column, expected, stop_code)
   end subroutine expect_csv_metadata_field

   subroutine expect_csv_entry_field(csv_text, name, column, expected, stop_code)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: name
      character(len=*), intent(in) :: column
      character(len=*), intent(in) :: expected
      integer, intent(in) :: stop_code

      call expect_csv_record_field(csv_text, 'entry', name, column, expected, stop_code)
   end subroutine expect_csv_entry_field

   subroutine expect_csv_record_field(csv_text, record_type, selector, column, expected, stop_code)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: record_type
      character(len=*), intent(in) :: selector
      character(len=*), intent(in) :: column
      character(len=*), intent(in) :: expected
      integer, intent(in) :: stop_code
      character(len=:), allocatable :: actual
      character(len=:), allocatable :: row
      integer :: column_idx

      row = find_csv_record(csv_text, record_type, selector)
      if (len(row) <= 0) error stop stop_code + 1000
      column_idx = csv_column_index_for_row(csv_text, row, column)
      if (column_idx <= 0) error stop stop_code
      actual = csv_field_value(row, column_idx)
      if ((len(actual) /= len(expected)) .or. (actual /= expected)) error stop stop_code + 2000
   end subroutine expect_csv_record_field

   integer function csv_column_index(csv_text, column) result(idx)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: column
      character(len=:), allocatable :: header
      character(len=:), allocatable :: value
      integer :: field_idx

      idx = 0
      header = first_line(csv_text)
      field_idx = 1
      do
         value = csv_field_value(header, field_idx)
         if ((len(value) <= 0) .and. (field_idx > csv_field_count(header))) exit
         if (value == column) then
            idx = field_idx
            return
         end if
         field_idx = field_idx + 1
         if (field_idx > csv_field_count(header)) exit
      end do
   end function csv_column_index

   integer function csv_column_index_for_row(csv_text, row, column) result(idx)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: row
      character(len=*), intent(in) :: column
      character(len=:), allocatable :: header
      character(len=:), allocatable :: row_value
      integer :: fallback_idx
      integer :: field_count
      integer :: field_idx

      idx = 0
      fallback_idx = 0
      header = first_line(csv_text)
      field_count = csv_field_count(header)
      do field_idx = 1, field_count
         if (csv_field_value(header, field_idx) /= column) cycle
         if (fallback_idx <= 0) fallback_idx = field_idx
         row_value = csv_field_value(row, field_idx)
         if (len(row_value) > 0) then
            idx = field_idx
            return
         end if
      end do
      idx = fallback_idx
   end function csv_column_index_for_row

   function find_csv_record(csv_text, record_type, selector) result(row)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: record_type
      character(len=*), intent(in) :: selector
      character(len=:), allocatable :: row
      character(len=:), allocatable :: candidate
      integer :: key_idx
      integer :: line_end
      integer :: line_start
      integer :: name_idx
      integer :: newline_pos

      row = ''
      key_idx = csv_column_index(csv_text, 'key')
      name_idx = csv_column_index(csv_text, 'name')
      line_start = len(first_line(csv_text)) + 2
      do while (line_start <= len(csv_text))
         newline_pos = index(csv_text(line_start:), new_line('a'))
         if (newline_pos <= 0) then
            line_end = len(csv_text)
         else
            line_end = line_start + newline_pos - 2
         end if
         if (line_end >= line_start) then
            candidate = csv_text(line_start:line_end)
            if (csv_field_value(candidate, 3) == record_type) then
               select case (record_type)
               case ('summary')
                  row = candidate
                  return
               case ('metadata')
                  if (csv_field_value(candidate, key_idx) == selector) then
                     row = candidate
                     return
                  end if
               case ('entry')
                  if (csv_field_value(candidate, name_idx) == selector) then
                     row = candidate
                     return
                  end if
               end select
            end if
         end if
         if (newline_pos <= 0) exit
         line_start = line_end + 2
      end do
   end function find_csv_record

   function csv_field_value(line, field_idx) result(value)
      character(len=*), intent(in) :: line
      integer, intent(in) :: field_idx
      character(len=:), allocatable :: value
      integer :: current_field
      integer :: i
      logical :: in_quotes
      logical :: pending_quote

      value = ''
      current_field = 1
      in_quotes = .false.
      pending_quote = .false.
      i = 1
      do while (i <= len_trim(line))
         if (pending_quote) then
            if (line(i:i) == '"') then
               if (current_field == field_idx) value = value//'"'
               pending_quote = .false.
               i = i + 1
               cycle
            end if
            in_quotes = .false.
            pending_quote = .false.
         end if

         if ((line(i:i) == ',') .and. (.not. in_quotes)) then
            if (current_field == field_idx) return
            current_field = current_field + 1
            i = i + 1
            cycle
         end if

         if (line(i:i) == '"') then
            if (in_quotes) then
               pending_quote = .true.
            else
               in_quotes = .true.
            end if
         elseif (current_field == field_idx) then
            value = value//line(i:i)
         end if
         i = i + 1
      end do
   end function csv_field_value

   integer function csv_field_count(line) result(count)
      character(len=*), intent(in) :: line
      integer :: i
      logical :: in_quotes

      count = 1
      in_quotes = .false.
      do i = 1, len_trim(line)
         if (line(i:i) == '"') then
            in_quotes = .not. in_quotes
         elseif ((line(i:i) == ',') .and. (.not. in_quotes)) then
            count = count + 1
         end if
      end do
   end function csv_field_count

   function csv_real_text(value) result(text)
      real(wp), intent(in) :: value
      character(len=:), allocatable :: text
      character(len=48) :: buffer

      write (buffer, '(es32.17e4)') value
      text = trim(adjustl(buffer))
   end function csv_real_text

   function csv_int_text(value) result(text)
      integer, intent(in) :: value
      character(len=:), allocatable :: text
      character(len=32) :: buffer

      write (buffer, '(i0)') value
      text = trim(buffer)
   end function csv_int_text

   function first_line(text) result(line)
      character(len=*), intent(in) :: text
      character(len=:), allocatable :: line
      integer :: newline_pos

      newline_pos = index(text, new_line('a'))
      if (newline_pos <= 0) then
         line = text
      elseif (newline_pos == 1) then
         line = ''
      else
         line = text(:newline_pos - 1)
      end if
   end function first_line

   integer function count_occurrences(text, needle) result(count)
      character(len=*), intent(in) :: text
      character(len=*), intent(in) :: needle
      integer :: pos
      integer :: start

      count = 0
      if (len(needle) <= 0) return
      start = 1
      do
         pos = index(text(start:), needle)
         if (pos <= 0) exit
         count = count + 1
         start = start + pos + len(needle) - 1
         if (start > len(text)) exit
      end do
   end function count_occurrences

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

      open (newunit=unit, file=path, status='replace', action='write', access='stream', form='unformatted', &
            iostat=io)
      if (io /= 0) error stop 910
      write (unit, iostat=io) text
      close (unit)
      if (io /= 0) error stop 911
   end subroutine write_text_file

   function read_file_text(path) result(text)
      character(len=*), intent(in) :: path
      character(len=:), allocatable :: text
      integer :: io
      integer :: size
      integer :: unit

      inquire (file=path, size=size)
      if (size <= 0) then
         text = ''
         return
      end if

      allocate (character(len=size) :: text)
      open (newunit=unit, file=path, access='stream', form='unformatted', action='read', iostat=io)
      if (io /= 0) error stop 900
      read (unit, iostat=io) text
      close (unit)
      if (io /= 0) error stop 901
   end function read_file_text

   function mock_openmp_clock() result(t)
      real(wp) :: t
      integer :: lane_id

      if (omp_in_parallel()) then
         lane_id = 1 + omp_get_thread_num()
      else
         lane_id = 0
      end if

      if ((lane_id < lbound(fake_lane_time, 1)) .or. (lane_id > ubound(fake_lane_time, 1))) then
         error stop "mock_openmp_clock lane id out of range"
      end if
      t = fake_lane_time(lane_id)
   end function mock_openmp_clock

end program ftimer_openmp_summary_smoke
