program ftimer_openmp_mpi_summary_smoke
   use, intrinsic :: iso_fortran_env, only: int64, iostat_end
   use ftimer_openmp, only: ftimer_mpi_openmp_summary_t, ftimer_openmp_config_t, &
                            ftimer_openmp_parallel_region_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_IO, FTIMER_ERR_MPI_INCON, &
                           FTIMER_SUCCESS, ftimer_metadata_t, wp
   use mpi_f08, only: MPI_Barrier, MPI_COMM_WORLD, MPI_Comm_rank, MPI_Comm_size, &
                      MPI_Finalize, MPI_Init, MPI_SUCCESS
   use omp_lib, only: omp_get_thread_num, omp_in_parallel, omp_set_dynamic, omp_set_num_threads
   implicit none

   real(wp), save :: fake_lane_time(0:4) = 0.0_wp
   integer :: ierr
   integer :: nprocs
   integer :: rank

   call MPI_Init(ierr)
   if (ierr /= MPI_SUCCESS) error stop 1

   call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
   if (ierr /= MPI_SUCCESS) error stop 2
   call MPI_Comm_size(MPI_COMM_WORLD, nprocs, ierr)
   if (ierr /= MPI_SUCCESS) error stop 3
   if (nprocs /= 2) error stop 4

   call omp_set_dynamic(.false.)
   call omp_set_num_threads(2)

   call check_strict_hybrid_identical_participation(rank)
   call check_strict_hybrid_active_lane_failure(rank)
   call check_strict_hybrid_open_region_failure(rank)
   call check_strict_hybrid_descriptor_mismatch(rank)
   call check_strict_hybrid_lane_participation_mismatch(rank)
   call check_strict_hybrid_execution_domain_mismatch(rank)
   call check_strict_hybrid_eligible_lane_mismatch(rank)
   call check_strict_hybrid_csv_append_validation(rank)

   call MPI_Finalize(ierr)
   if (ierr /= MPI_SUCCESS) error stop 5

contains

   subroutine check_strict_hybrid_identical_participation(rank)
      integer, intent(in) :: rank
      character(len=*), parameter :: csv_path = 'mpi_openmp_summary.csv'
      character(len=*), parameter :: report_path = 'mpi_openmp_summary.txt'
      type(ftimer_metadata_t) :: metadata(1)
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      character(len=:), allocatable :: csv_text
      character(len=:), allocatable :: report_text
      integer :: child_id
      integer :: child_idx
      integer :: ierr
      integer :: root_id
      integer :: root_idx

      if (rank == 0) then
         call delete_if_exists(report_path)
         call delete_if_exists(csv_path)
      end if
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 10

      config%max_lanes = 3
      config%max_worker_diagnostics = 4
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 11)

      fake_lane_time(0) = 100.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 12)

      call timer%register_timer('root', root_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 13)
      call timer%register_timer('child', child_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 14)

      fake_lane_time(0) = 110.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 15)

!$omp parallel num_threads(2) default(shared) private(ierr)
      if (omp_get_thread_num() == 0) then
         fake_lane_time(1) = 0.0_wp
         call timer%start_id(root_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 16
         fake_lane_time(1) = 2.0_wp
         call timer%start_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 17
         fake_lane_time(1) = merge(5.0_wp, 8.0_wp, rank == 0)
         call timer%stop_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 18
         fake_lane_time(1) = merge(10.0_wp, 20.0_wp, rank == 0)
         call timer%stop_id(root_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 19
      else
         fake_lane_time(2) = 0.0_wp
         call timer%start_id(root_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 20
         fake_lane_time(2) = 3.0_wp
         call timer%start_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 21
         fake_lane_time(2) = merge(7.0_wp, 11.0_wp, rank == 0)
         call timer%stop_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 22
         fake_lane_time(2) = merge(12.0_wp, 22.0_wp, rank == 0)
         call timer%stop_id(root_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 23
      end if
!$omp end parallel

      fake_lane_time(0) = merge(120.0_wp, 130.0_wp, rank == 0)
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 24)

      fake_lane_time(0) = merge(125.0_wp, 135.0_wp, rank == 0)
      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 25)

      call expect_int(summary%num_ranks, 2, 26)
      call expect_int(summary%num_entries, 2, 27)
      call expect_time(summary%min_rank_summary_window_time, 25.0_wp, 28)
      call expect_time(summary%avg_rank_summary_window_time, 30.0_wp, 29)
      call expect_time(summary%max_rank_summary_window_time, 35.0_wp, 30)
      call expect_time(summary%rank_summary_window_imbalance, 35.0_wp/30.0_wp, 31)
      call expect_time(summary%min_rank_timed_region_envelope_time, 10.0_wp, 32)
      call expect_time(summary%avg_rank_timed_region_envelope_time, 15.0_wp, 33)
      call expect_time(summary%max_rank_timed_region_envelope_time, 20.0_wp, 34)
      call expect_time(summary%min_rank_sum_lane_root_inclusive_time, 22.0_wp, 35)
      call expect_time(summary%avg_rank_sum_lane_root_inclusive_time, 32.0_wp, 36)
      call expect_time(summary%max_rank_sum_lane_root_inclusive_time, 42.0_wp, 37)
      call expect_int(size(summary%ranks), 2, 38)
      call expect_int(summary%ranks(1)%rank, 0, 39)
      call expect_time(summary%ranks(1)%sum_lane_root_inclusive_time, 22.0_wp, 40)
      call expect_int(summary%ranks(2)%rank, 1, 41)
      call expect_time(summary%ranks(2)%sum_lane_root_inclusive_time, 42.0_wp, 42)

      root_idx = find_entry(summary, 'root', 0)
      if (root_idx <= 0) error stop 43
      child_idx = find_entry(summary, 'child', summary%entries(root_idx)%node_id)
      if (child_idx <= 0) error stop 44

      call expect_entry(summary, root_idx, rank_count=2, eligible_samples=4, participating_samples=4, &
                        missing_samples=0, sum_inclusive=64.0_wp, sum_self=43.0_wp, &
                        min_inclusive=10.0_wp, avg_inclusive=16.0_wp, max_inclusive=22.0_wp, &
                        inclusive_imbalance=22.0_wp/16.0_wp, min_self=7.0_wp, avg_self=10.75_wp, &
                        max_self=14.0_wp, self_imbalance=14.0_wp/10.75_wp, &
                        min_calls=1_int64, avg_calls=1.0_wp, max_calls=1_int64, stop_code=45)
      call expect_entry(summary, child_idx, rank_count=2, eligible_samples=4, participating_samples=4, &
                        missing_samples=0, sum_inclusive=21.0_wp, sum_self=21.0_wp, &
                        min_inclusive=3.0_wp, avg_inclusive=5.25_wp, max_inclusive=8.0_wp, &
                        inclusive_imbalance=8.0_wp/5.25_wp, min_self=3.0_wp, avg_self=5.25_wp, &
                        max_self=8.0_wp, self_imbalance=8.0_wp/5.25_wp, &
                        min_calls=1_int64, avg_calls=1.0_wp, max_calls=1_int64, stop_code=46)
      call expect_time(summary%entries(root_idx)%min_participating_lane_pct_time, 40.0_wp, 47)
      call expect_time(summary%entries(root_idx)%avg_participating_lane_pct_time, 52.0_wp, 48)
      call expect_time(summary%entries(root_idx)%max_participating_lane_pct_time, 100.0_wp*22.0_wp/35.0_wp, 49)

      metadata(1)%key = 'Case'
      metadata(1)%value = 'strict hybrid'
      call timer%write_mpi_openmp_summary(report_path, metadata=metadata, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 50)
      call timer%write_mpi_openmp_summary_csv(csv_path, metadata=metadata, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 51)
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 52

      if (rank == 0) then
         report_text = read_file_text(report_path)
         call expect_contains(report_text, 'MPI+OpenMP summary', 53)
         call expect_contains(report_text, 'Rank timed-region envelope', 54)
         call expect_contains(report_text, 'Rank/lane samples', 55)
         call expect_contains(report_text, 'strict hybrid', 56)

         csv_text = read_file_text(csv_path)
         call expect_contains(csv_text, 'summary_kind', 57)
         call expect_contains(csv_text, 'mpi_openmp', 58)
         call expect_contains(csv_text, 'eligible_rank_lane_sample_count', 59)
         call expect_contains(csv_text, 'avg_participating_lane_pct_time', 60)
         call expect_contains(csv_text, '"1","mpi_openmp","summary"', 61)
         call expect_contains(csv_text, '"1","mpi_openmp","rank"', 62)
         call expect_contains(csv_text, '"1","mpi_openmp","entry"', 63)
         call expect_not_contains(csv_text, '"2","mpi","summary"', 64)
         call expect_csv_record_count(csv_text, 'summary', 1, 65)
         call expect_csv_record_count(csv_text, 'rank', 2, 66)
         call expect_csv_record_count(csv_text, 'entry', 2, 67)
         call expect_csv_record_field(csv_text, 'summary', '', 'num_ranks', '2', 68)
         call expect_csv_record_field(csv_text, 'summary', '', 'num_entries', '2', 69)
         call expect_csv_record_field(csv_text, 'rank', '0', 'sum_lane_root_inclusive_time', &
                                      real_csv_text(22.0_wp), 70)
         call expect_csv_record_field(csv_text, 'rank', '1', 'sum_lane_root_inclusive_time', &
                                      real_csv_text(42.0_wp), 71)
         call expect_csv_record_field(csv_text, 'entry', 'root', 'execution_domain', &
                                      'openmp_level1_team', 72)
         call expect_csv_record_field(csv_text, 'entry', 'root', 'eligible_rank_lane_sample_count', '4', 73)
         call expect_csv_record_field(csv_text, 'entry', 'root', 'participating_rank_lane_sample_count', '4', 74)
         call expect_csv_real_record_field(csv_text, 'entry', 'root', &
                                          'sum_participating_lane_self_time', 43.0_wp, 75)
         call expect_csv_record_field(csv_text, 'entry', 'root', 'min_participating_lane_call_count', '1', 76)
         call expect_csv_record_field(csv_text, 'entry', 'child', 'parent_id', &
                                      int_csv_text(summary%entries(root_idx)%node_id), 77)
      end if

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 78)
      if (rank == 0) then
         call delete_if_exists(report_path)
         call delete_if_exists(csv_path)
      end if
   end subroutine check_strict_hybrid_identical_participation

   subroutine check_strict_hybrid_active_lane_failure(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: active_id
      integer :: ierr

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 70)
      fake_lane_time(0) = 200.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 71)
      call timer%register_timer('active', active_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 72)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 73)
!$omp parallel num_threads(2) default(shared) private(ierr)
      if ((rank == 0) .and. (omp_get_thread_num() == 0)) then
         fake_lane_time(1) = 0.0_wp
         call timer%start_id(active_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 74
      end if
!$omp end parallel

      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 75)
      call expect_int(summary%num_entries, 0, 76)

!$omp parallel num_threads(2) default(shared) private(ierr)
      if ((rank == 0) .and. (omp_get_thread_num() == 0)) then
         fake_lane_time(1) = 4.0_wp
         call timer%stop_id(active_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 77
      end if
!$omp end parallel
      fake_lane_time(0) = 206.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 78)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 79)
   end subroutine check_strict_hybrid_active_lane_failure

   subroutine check_strict_hybrid_open_region_failure(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: ierr

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 110)
      fake_lane_time(0) = 250.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 111)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 112)
      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 113)
      call expect_int(summary%num_entries, 0, 114)
      fake_lane_time(0) = 252.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 115)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 116)
   end subroutine check_strict_hybrid_open_region_failure

   subroutine check_strict_hybrid_descriptor_mismatch(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: timer_id

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 80)
      fake_lane_time(0) = 300.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 81)
      if (rank == 0) then
         call timer%register_timer('same_on_rank0', timer_id, ierr=ierr)
      else
         call timer%register_timer('different_on_rank1', timer_id, ierr=ierr)
      end if
      call expect_status(ierr, FTIMER_SUCCESS, 82)
      call run_all_worker_lanes(timer, region, timer_id, 1.0_wp, 2.0_wp, 83)

      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_MPI_INCON, 84)
      call expect_int(summary%num_entries, 0, 85)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 86)
   end subroutine check_strict_hybrid_descriptor_mismatch

   subroutine check_strict_hybrid_lane_participation_mismatch(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: timer_id

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 90)
      fake_lane_time(0) = 400.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 91)
      call timer%register_timer('lane_required', timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 92)

      fake_lane_time(0) = 410.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 93)
!$omp parallel num_threads(2) default(shared) private(ierr)
      if ((rank == 0) .or. (omp_get_thread_num() == 0)) then
         fake_lane_time(1 + omp_get_thread_num()) = 1.0_wp
         call timer%start_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 94
         fake_lane_time(1 + omp_get_thread_num()) = 3.0_wp
         call timer%stop_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 95
      end if
!$omp end parallel
      fake_lane_time(0) = 415.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 96)

      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_MPI_INCON, 97)
      call expect_int(summary%num_entries, 0, 98)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 99)
   end subroutine check_strict_hybrid_lane_participation_mismatch

   subroutine check_strict_hybrid_execution_domain_mismatch(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: timer_id

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 130)
      fake_lane_time(0) = 500.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 131)
      call timer%register_timer('same_domain_sensitive', timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 132)

      if (rank == 0) then
         fake_lane_time(0) = 1.0_wp
         call timer%start_id(timer_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 133)
         fake_lane_time(0) = 3.0_wp
         call timer%stop_id(timer_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 134)
      else
         call run_all_worker_lanes(timer, region, timer_id, 1.0_wp, 3.0_wp, 135)
      end if

      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_MPI_INCON, 137)
      call expect_int(summary%num_entries, 0, 138)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 139)
   end subroutine check_strict_hybrid_execution_domain_mismatch

   subroutine check_strict_hybrid_eligible_lane_mismatch(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: timer_id

      config%max_lanes = 4
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 150)
      fake_lane_time(0) = 600.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 151)
      call timer%register_timer('same_lane_sensitive', timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 152)

      fake_lane_time(0) = 610.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 153)
!$omp parallel num_threads(merge(2, 3, rank == 0)) default(shared) private(ierr)
      fake_lane_time(1 + omp_get_thread_num()) = 1.0_wp
      call timer%start_id(timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 154
      fake_lane_time(1 + omp_get_thread_num()) = 4.0_wp
      call timer%stop_id(timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 155
!$omp end parallel
      fake_lane_time(0) = 616.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 156)

      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_MPI_INCON, 157)
      call expect_int(summary%num_entries, 0, 158)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 159)
   end subroutine check_strict_hybrid_eligible_lane_mismatch

   subroutine check_strict_hybrid_csv_append_validation(rank)
      integer, intent(in) :: rank
      character(len=*), parameter :: bad_record_path = 'mpi_openmp_summary_bad_record_append.csv'
      character(len=*), parameter :: csv_path = 'mpi_openmp_summary_append.csv'
      character(len=*), parameter :: truncated_path = 'mpi_openmp_summary_truncated_append.csv'
      character(len=*), parameter :: unknown_record_path = 'mpi_openmp_summary_unknown_record_append.csv'
      character(len=*), parameter :: wrong_header_path = 'mpi_openmp_summary_wrong_header_append.csv'
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      character(len=:), allocatable :: bad_text
      character(len=:), allocatable :: csv_text
      character(len=:), allocatable :: header
      integer :: ierr
      integer :: timer_id

      if (rank == 0) then
         call delete_if_exists(csv_path)
         call delete_if_exists(bad_record_path)
         call delete_if_exists(truncated_path)
         call delete_if_exists(unknown_record_path)
         call delete_if_exists(wrong_header_path)
      end if
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 180

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 181)
      fake_lane_time(0) = 700.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 182)
      call timer%register_timer('append', timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 183)
      call run_all_worker_lanes(timer, region, timer_id, 1.0_wp, 3.0_wp, 184)

      call timer%write_mpi_openmp_summary_csv(csv_path, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 186)
      call timer%write_mpi_openmp_summary_csv(csv_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 187)
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 188

      if (rank == 0) then
         csv_text = read_file_text(csv_path)
         header = first_line(csv_text)
         call expect_int(count_occurrences(csv_text, header), 1, 189)

         bad_text = header//new_line('a')//'"1","mpi_openmp","summary"'//new_line('a')
         call write_text_file(bad_record_path, bad_text)
         bad_text = header//new_line('a')//'"1","mpi_openmp","summary",'
         call write_text_file(truncated_path, bad_text)
         bad_text = header//new_line('a')// &
                    replace_first(csv_line_at(csv_text, 2), '"summary"', '"invalid"')//new_line('a')
         call write_text_file(unknown_record_path, bad_text)
         bad_text = 'format_version,summary_kind,record_type'//new_line('a')
         call write_text_file(wrong_header_path, bad_text)
      end if
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 190

      call timer%write_mpi_openmp_summary_csv(bad_record_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 191)
      call timer%write_mpi_openmp_summary_csv(truncated_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 192)
      call timer%write_mpi_openmp_summary_csv(unknown_record_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 193)
      call timer%write_mpi_openmp_summary_csv(wrong_header_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 194)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 195)
      if (rank == 0) then
         call delete_if_exists(csv_path)
         call delete_if_exists(bad_record_path)
         call delete_if_exists(truncated_path)
         call delete_if_exists(unknown_record_path)
         call delete_if_exists(wrong_header_path)
      end if
   end subroutine check_strict_hybrid_csv_append_validation

   subroutine run_all_worker_lanes(timer, region, timer_id, start_time, stop_time, stop_code)
      type(ftimer_openmp_t), intent(inout) :: timer
      type(ftimer_openmp_parallel_region_t), intent(inout) :: region
      integer, intent(in) :: timer_id
      real(wp), intent(in) :: start_time
      real(wp), intent(in) :: stop_time
      integer, intent(in) :: stop_code
      integer :: ierr

      fake_lane_time(0) = 0.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, stop_code)
!$omp parallel num_threads(2) default(shared) private(ierr)
      fake_lane_time(1 + omp_get_thread_num()) = start_time
      call timer%start_id(timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 100
      fake_lane_time(1 + omp_get_thread_num()) = stop_time
      call timer%stop_id(timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 101
!$omp end parallel
      fake_lane_time(0) = 5.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, stop_code + 1)
   end subroutine run_all_worker_lanes

   integer function find_entry(summary, name, parent_id) result(idx)
      type(ftimer_mpi_openmp_summary_t), intent(in) :: summary
      character(len=*), intent(in) :: name
      integer, intent(in) :: parent_id
      integer :: i

      idx = 0
      do i = 1, summary%num_entries
         if (summary%entries(i)%parent_id /= parent_id) cycle
         if (trim(summary%entries(i)%name) /= name) cycle
         idx = i
         return
      end do
   end function find_entry

   subroutine expect_entry(summary, idx, rank_count, eligible_samples, participating_samples, &
                           missing_samples, sum_inclusive, sum_self, min_inclusive, avg_inclusive, &
                           max_inclusive, inclusive_imbalance, min_self, avg_self, max_self, &
                           self_imbalance, min_calls, avg_calls, max_calls, stop_code)
      type(ftimer_mpi_openmp_summary_t), intent(in) :: summary
      integer, intent(in) :: idx
      integer, intent(in) :: rank_count
      integer, intent(in) :: eligible_samples
      integer, intent(in) :: participating_samples
      integer, intent(in) :: missing_samples
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

      call expect_int(summary%entries(idx)%participating_rank_count, rank_count, stop_code)
      call expect_int(summary%entries(idx)%missing_rank_count, 0, stop_code + 1)
      call expect_int(summary%entries(idx)%eligible_rank_lane_sample_count, eligible_samples, stop_code + 2)
      call expect_int(summary%entries(idx)%participating_rank_lane_sample_count, &
                      participating_samples, stop_code + 3)
      call expect_int(summary%entries(idx)%missing_rank_lane_sample_count, missing_samples, stop_code + 4)
      if (.not. summary%entries(idx)%missing_rank_lane_sample_count_known) error stop stop_code + 5
      call expect_time(summary%entries(idx)%sum_participating_lane_inclusive_time, &
                       sum_inclusive, stop_code + 6)
      call expect_time(summary%entries(idx)%sum_participating_lane_self_time, sum_self, stop_code + 7)
      call expect_time(summary%entries(idx)%min_participating_lane_inclusive_time, &
                       min_inclusive, stop_code + 8)
      call expect_time(summary%entries(idx)%avg_participating_lane_inclusive_time, &
                       avg_inclusive, stop_code + 9)
      call expect_time(summary%entries(idx)%max_participating_lane_inclusive_time, &
                       max_inclusive, stop_code + 10)
      call expect_time(summary%entries(idx)%participating_lane_inclusive_imbalance, &
                       inclusive_imbalance, stop_code + 11)
      call expect_time(summary%entries(idx)%min_participating_lane_self_time, min_self, stop_code + 12)
      call expect_time(summary%entries(idx)%avg_participating_lane_self_time, avg_self, stop_code + 13)
      call expect_time(summary%entries(idx)%max_participating_lane_self_time, max_self, stop_code + 14)
      call expect_time(summary%entries(idx)%participating_lane_self_imbalance, self_imbalance, stop_code + 15)
      call expect_int64(summary%entries(idx)%min_participating_lane_call_count, min_calls, stop_code + 16)
      call expect_time(summary%entries(idx)%avg_participating_lane_call_count, avg_calls, stop_code + 17)
      call expect_int64(summary%entries(idx)%max_participating_lane_call_count, max_calls, stop_code + 18)
   end subroutine expect_entry

   real(wp) function mock_openmp_clock() result(t)
      integer :: lane_id

      lane_id = current_test_lane_id()
      t = fake_lane_time(lane_id)
   end function mock_openmp_clock

   integer function current_test_lane_id() result(lane_id)
      lane_id = 0
      if (omp_in_parallel()) lane_id = 1 + omp_get_thread_num()
      if (lane_id < 0 .or. lane_id > ubound(fake_lane_time, 1)) lane_id = 0
   end function current_test_lane_id

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

      if (abs(actual - expected) > 1.0e-9_wp) error stop stop_code
   end subroutine expect_time

   subroutine expect_contains(text, needle, stop_code)
      character(len=*), intent(in) :: text
      character(len=*), intent(in) :: needle
      integer, intent(in) :: stop_code

      if (index(text, needle) <= 0) error stop stop_code
   end subroutine expect_contains

   subroutine expect_not_contains(text, needle, stop_code)
      character(len=*), intent(in) :: text
      character(len=*), intent(in) :: needle
      integer, intent(in) :: stop_code

      if (index(text, needle) > 0) error stop stop_code
   end subroutine expect_not_contains

   subroutine expect_csv_record_count(csv_text, record_type, expected, stop_code)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: record_type
      integer, intent(in) :: expected
      integer, intent(in) :: stop_code
      character(len=:), allocatable :: candidate
      integer :: count
      integer :: line_no
      integer :: record_type_col

      record_type_col = csv_column_index(first_line(csv_text), 'record_type')
      if (record_type_col <= 0) error stop stop_code
      count = 0
      line_no = 2
      do
         candidate = csv_line_at(csv_text, line_no)
         if (len(candidate) <= 0) exit
         if (csv_field_value(candidate, record_type_col) == record_type) count = count + 1
         line_no = line_no + 1
      end do
      if (count /= expected) error stop stop_code
   end subroutine expect_csv_record_count

   subroutine expect_csv_record_field(csv_text, record_type, selector, column, expected, stop_code)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: record_type
      character(len=*), intent(in) :: selector
      character(len=*), intent(in) :: column
      character(len=*), intent(in) :: expected
      integer, intent(in) :: stop_code
      character(len=:), allocatable :: header
      character(len=:), allocatable :: row
      integer :: column_idx

      header = first_line(csv_text)
      row = find_csv_record(csv_text, record_type, selector)
      if (len(row) <= 0) error stop stop_code
      column_idx = csv_column_index(header, column)
      if (column_idx <= 0) error stop stop_code
      if (csv_field_value(row, column_idx) /= expected) error stop stop_code
   end subroutine expect_csv_record_field

   subroutine expect_csv_real_record_field(csv_text, record_type, selector, column, expected, stop_code)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: record_type
      character(len=*), intent(in) :: selector
      character(len=*), intent(in) :: column
      real(wp), intent(in) :: expected
      integer, intent(in) :: stop_code
      character(len=:), allocatable :: field_text
      character(len=:), allocatable :: header
      character(len=:), allocatable :: row
      integer :: column_idx
      integer :: io
      real(wp) :: actual

      header = first_line(csv_text)
      row = find_csv_record(csv_text, record_type, selector)
      if (len(row) <= 0) error stop stop_code
      column_idx = csv_column_index(header, column)
      if (column_idx <= 0) error stop stop_code
      field_text = csv_field_value(row, column_idx)
      read (field_text, *, iostat=io) actual
      if (io /= 0) error stop stop_code
      call expect_time(actual, expected, stop_code)
   end subroutine expect_csv_real_record_field

   function find_csv_record(csv_text, record_type, selector) result(row)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: record_type
      character(len=*), intent(in) :: selector
      character(len=:), allocatable :: row
      character(len=:), allocatable :: candidate
      character(len=:), allocatable :: header
      integer :: line_no
      integer :: name_col
      integer :: rank_col
      integer :: record_type_col

      row = ''
      header = first_line(csv_text)
      record_type_col = csv_column_index(header, 'record_type')
      rank_col = csv_column_index(header, 'rank')
      name_col = csv_column_index(header, 'name')
      if (record_type_col <= 0) return
      line_no = 2
      do
         candidate = csv_line_at(csv_text, line_no)
         if (len(candidate) <= 0) exit
         if (csv_field_value(candidate, record_type_col) == record_type) then
            select case (record_type)
            case ('summary')
               if (len_trim(selector) == 0) then
                  row = candidate
                  return
               end if
            case ('rank')
               if ((rank_col > 0) .and. (csv_field_value(candidate, rank_col) == selector)) then
                  row = candidate
                  return
               end if
            case ('entry')
               if ((name_col > 0) .and. (csv_field_value(candidate, name_col) == selector)) then
                  row = candidate
                  return
               end if
            end select
         end if
         line_no = line_no + 1
      end do
   end function find_csv_record

   integer function csv_column_index(header, column_name) result(idx)
      character(len=*), intent(in) :: header
      character(len=*), intent(in) :: column_name
      integer :: column
      integer :: pos

      idx = 0
      column = 1
      pos = 1
      do while (pos <= len_trim(header))
         if (csv_field_value(header, column) == column_name) then
            idx = column
            return
         end if
         column = column + 1
         pos = next_csv_field_start(header, pos)
         if (pos <= 0) exit
      end do
   end function csv_column_index

   integer function next_csv_field_start(line, start_pos) result(next_pos)
      character(len=*), intent(in) :: line
      integer, intent(in) :: start_pos
      integer :: i
      logical :: in_quotes
      logical :: pending_quote

      next_pos = 0
      in_quotes = .false.
      pending_quote = .false.
      i = start_pos
      do while (i <= len_trim(line))
         if (pending_quote) then
            pending_quote = .false.
            if (line(i:i) == '"') then
               i = i + 1
               cycle
            end if
            in_quotes = .false.
         end if
         if (line(i:i) == '"') then
            if (in_quotes) then
               pending_quote = .true.
            else
               in_quotes = .true.
            end if
         else if ((line(i:i) == ',') .and. (.not. in_quotes)) then
            next_pos = i + 1
            return
         end if
         i = i + 1
      end do
   end function next_csv_field_start

   function csv_field_value(line, column) result(value)
      character(len=*), intent(in) :: line
      integer, intent(in) :: column
      character(len=:), allocatable :: value
      integer :: current_column
      integer :: i
      logical :: in_quotes
      logical :: pending_quote

      value = ''
      current_column = 1
      in_quotes = .false.
      pending_quote = .false.
      i = 1
      do while (i <= len_trim(line))
         if (pending_quote) then
            pending_quote = .false.
            if (line(i:i) == '"') then
               if (current_column == column) value = value//'"'
               i = i + 1
               cycle
            end if
            in_quotes = .false.
         end if
         if (line(i:i) == '"') then
            if (in_quotes) then
               pending_quote = .true.
            else
               in_quotes = .true.
            end if
         else if ((line(i:i) == ',') .and. (.not. in_quotes)) then
            if (current_column == column) return
            current_column = current_column + 1
         else if (current_column == column) then
            value = value//line(i:i)
         end if
         i = i + 1
      end do
   end function csv_field_value

   function first_line(text) result(line)
      character(len=*), intent(in) :: text
      character(len=:), allocatable :: line

      line = csv_line_at(text, 1)
   end function first_line

   function csv_line_at(text, line_no) result(line)
      character(len=*), intent(in) :: text
      integer, intent(in) :: line_no
      character(len=:), allocatable :: line
      integer :: current_line
      integer :: i

      line = ''
      current_line = 1
      do i = 1, len(text)
         if (text(i:i) == new_line('a')) then
            if (current_line == line_no) return
            current_line = current_line + 1
            cycle
         end if
         if (current_line == line_no) line = line//text(i:i)
      end do
   end function csv_line_at

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

   function replace_first(text, old, new) result(replaced)
      character(len=*), intent(in) :: text
      character(len=*), intent(in) :: old
      character(len=*), intent(in) :: new
      character(len=:), allocatable :: replaced
      integer :: pos

      pos = index(text, old)
      if (pos <= 0) then
         replaced = text
      else
         replaced = text(:pos - 1)//new//text(pos + len(old):)
      end if
   end function replace_first

   function int_csv_text(value) result(text)
      integer, intent(in) :: value
      character(len=:), allocatable :: text
      character(len=32) :: buffer

      write (buffer, '(i0)') value
      text = trim(buffer)
   end function int_csv_text

   function real_csv_text(value) result(text)
      real(wp), intent(in) :: value
      character(len=:), allocatable :: text
      character(len=48) :: buffer

      write (buffer, '(es32.17e4)') value
      text = trim(adjustl(buffer))
   end function real_csv_text

   function read_file_text(path) result(text)
      character(len=*), intent(in) :: path
      character(len=:), allocatable :: text
      character(len=1) :: ch
      integer :: io
      integer :: unit

      text = ''
      open (newunit=unit, file=path, status='old', access='stream', form='unformatted', action='read', iostat=io)
      if (io /= 0) error stop 200
      do
         read (unit, iostat=io) ch
         if (io == iostat_end) exit
         if (io /= 0) error stop 201
         text = text//ch
      end do
      close (unit)
   end function read_file_text

   subroutine write_text_file(path, text)
      character(len=*), intent(in) :: path
      character(len=*), intent(in) :: text
      integer :: io
      integer :: unit

      open (newunit=unit, file=path, status='replace', action='write', iostat=io)
      if (io /= 0) error stop 202
      write (unit, '(a)', advance='no', iostat=io) text
      if (io /= 0) error stop 203
      close (unit, iostat=io)
      if (io /= 0) error stop 204
   end subroutine write_text_file

   subroutine delete_if_exists(path)
      character(len=*), intent(in) :: path
      integer :: io
      integer :: unit
      logical :: exists

      inquire (file=path, exist=exists)
      if (.not. exists) return
      open (newunit=unit, file=path, status='old', iostat=io)
      if (io == 0) close (unit, status='delete')
   end subroutine delete_if_exists
end program ftimer_openmp_mpi_summary_smoke
