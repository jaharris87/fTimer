program ftimer_openmp_summary_smoke
   use, intrinsic :: iso_fortran_env, only: int64
   use omp_lib, only: omp_get_thread_num, omp_in_parallel, omp_set_dynamic, omp_set_num_threads
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_parallel_region_t, &
                            ftimer_openmp_summary_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_SUCCESS, ftimer_metadata_t, wp
   implicit none

   real(wp), save :: fake_lane_time(0:4) = 0.0_wp

   call omp_set_dynamic(.false.)
   call omp_set_num_threads(2)

   call check_openmp_summary_aggregates()
   call check_openmp_summary_active_refusal()

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
                        avg_self=9.5_wp, min_calls=1_int64, avg_calls=1.0_wp, max_calls=1_int64, stop_code=25)
      call expect_entry(summary, child_idx, eligible=2, participating=1, missing=1, &
                        sum_inclusive=3.0_wp, sum_self=3.0_wp, &
                        min_inclusive=3.0_wp, avg_inclusive=3.0_wp, max_inclusive=3.0_wp, &
                        avg_self=3.0_wp, min_calls=1_int64, avg_calls=1.0_wp, max_calls=1_int64, stop_code=26)
      call expect_entry(summary, serial_idx, eligible=1, participating=1, missing=0, &
                        sum_inclusive=2.0_wp, sum_self=2.0_wp, &
                        min_inclusive=2.0_wp, avg_inclusive=2.0_wp, max_inclusive=2.0_wp, &
                        avg_self=2.0_wp, min_calls=1_int64, avg_calls=1.0_wp, max_calls=1_int64, stop_code=27)
      call expect_entry(summary, sparse_idx, eligible=2, participating=1, missing=1, &
                        sum_inclusive=5.0_wp, sum_self=5.0_wp, &
                        min_inclusive=5.0_wp, avg_inclusive=5.0_wp, max_inclusive=5.0_wp, &
                        avg_self=5.0_wp, min_calls=1_int64, avg_calls=1.0_wp, max_calls=1_int64, stop_code=28)

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

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 47)
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

   subroutine expect_entry(summary, idx, eligible, participating, missing, sum_inclusive, sum_self, &
                           min_inclusive, avg_inclusive, max_inclusive, avg_self, &
                           min_calls, avg_calls, max_calls, stop_code)
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
      real(wp), intent(in) :: avg_self
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
      call expect_time(summary%entries(idx)%avg_lane_self_time, avg_self, stop_code + 900)
      call expect_int64(summary%entries(idx)%min_lane_call_count, min_calls, stop_code + 1000)
      call expect_time(summary%entries(idx)%avg_lane_call_count, avg_calls, stop_code + 1100)
      call expect_int64(summary%entries(idx)%max_lane_call_count, max_calls, stop_code + 1200)
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

   subroutine delete_if_exists(path)
      character(len=*), intent(in) :: path
      integer :: io
      integer :: unit

      open (newunit=unit, file=path, status='old', iostat=io)
      if (io == 0) close (unit, status='delete')
   end subroutine delete_if_exists

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
