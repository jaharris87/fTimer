program ftimer_openmp_mpi_summary_smoke
   use, intrinsic :: iso_fortran_env, only: int64, iostat_end
   use ftimer_openmp, only: ftimer_mpi_openmp_summary_t, ftimer_mpi_openmp_union_summary_t, &
                            ftimer_openmp_config_t, &
                            ftimer_openmp_parallel_region_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_IO, FTIMER_ERR_MPI_INCON, &
                           FTIMER_ERR_NOT_INIT, FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS, &
                           ftimer_metadata_t, wp
   use mpi_f08, only: MPI_Barrier, MPI_COMM_NULL, MPI_COMM_WORLD, MPI_Comm, &
                      MPI_Comm_free, MPI_Comm_rank, MPI_Comm_size, MPI_Comm_split, &
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
   call check_sparse_hybrid_rank_lane_participation(rank)
   call check_sparse_hybrid_active_lane_failure(rank)
   call check_strict_hybrid_serial_lane_success(rank)
   call check_strict_hybrid_registration_order_independent(rank)
   call check_strict_hybrid_null_comm_failure(rank)
   call check_strict_hybrid_post_finalize_subcomm_failure(rank)
   call check_strict_hybrid_uninitialized_rank_failure(rank)
   call check_strict_hybrid_active_lane_failure(rank)
   call check_strict_hybrid_serial_lane_active_failure(rank)
   call check_strict_hybrid_open_region_failure(rank)
   call check_strict_hybrid_parallel_entry_local_failure(rank)
   call check_strict_hybrid_descriptor_mismatch(rank)
   call check_strict_hybrid_same_name_contexts(rank)
   call check_strict_hybrid_context_path_mismatch(rank)
   call check_strict_hybrid_lane_participation_mismatch(rank)
   call check_strict_hybrid_execution_domain_mismatch(rank)
   call check_strict_hybrid_eligible_lane_mismatch(rank)
   call check_strict_hybrid_varied_call_counts(rank)
   call check_strict_hybrid_worker_varied_call_counts(rank)
   call check_strict_hybrid_worker_context_call_counts(rank)
   call check_strict_hybrid_worker_diagnostic_ierr_preflight(rank)
   call check_strict_hybrid_worker_diagnostic_no_ierr_failure(rank)
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
      call expect_time(summary%min_rank_sum_lane_self_time, 22.0_wp, 1000)
      call expect_time(summary%avg_rank_sum_lane_self_time, 32.0_wp, 1001)
      call expect_time(summary%max_rank_sum_lane_self_time, 42.0_wp, 1002)
      call expect_int(summary%min_rank_summary_window_time_rank, 0, 1003)
      call expect_int(summary%max_rank_summary_window_time_rank, 1, 1004)
      call expect_int(summary%min_rank_timed_region_envelope_time_rank, 0, 1005)
      call expect_int(summary%max_rank_timed_region_envelope_time_rank, 1, 1006)
      call expect_int(summary%min_rank_sum_lane_root_inclusive_time_rank, 0, 1007)
      call expect_int(summary%max_rank_sum_lane_root_inclusive_time_rank, 1, 1008)
      call expect_int(summary%min_rank_sum_lane_self_time_rank, 0, 1009)
      call expect_int(summary%max_rank_sum_lane_self_time_rank, 1, 1010)
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
         call expect_contains(report_text, 'root', 57)
         call expect_contains(report_text, 'child', 58)
         call expect_contains(report_text, '25.000000 / 30.000000 / 35.000000', 59)
         call expect_contains(report_text, '10.000000 / 15.000000 / 20.000000', 60)
         call expect_contains(report_text, '22.000000 / 32.000000 / 42.000000', 61)
         call expect_contains(report_text, 'Rank  Lanes', 62)
         call expect_contains(report_text, 'openmp_level1_team', 63)
         call expect_contains(report_text, '64.000000', 64)
         call expect_contains(report_text, '43.000000', 65)
         call expect_contains(report_text, '21.000000', 66)
         call expect_contains(report_text, '5.250000', 67)
         call expect_report_entry_line(report_text, 'root', 2, 4, 0, 64.0_wp, 43.0_wp, &
                                       10.0_wp, 16.0_wp, 22.0_wp, 1.0_wp, 68)
         call expect_report_entry_line(report_text, 'child', 2, 4, 0, 21.0_wp, 21.0_wp, &
                                       3.0_wp, 5.25_wp, 8.0_wp, 1.0_wp, 69)

         csv_text = read_file_text(csv_path)
         call expect_contains(csv_text, 'summary_kind', 70)
         call expect_contains(csv_text, 'mpi_openmp', 71)
         call expect_contains(csv_text, 'eligible_rank_lane_sample_count', 72)
         call expect_contains(csv_text, 'avg_participating_lane_pct_time', 73)
         call expect_contains(csv_text, '"1","mpi_openmp","summary"', 74)
         call expect_contains(csv_text, '"1","mpi_openmp","rank"', 75)
         call expect_contains(csv_text, '"1","mpi_openmp","entry"', 76)
         call expect_not_contains(csv_text, '"2","mpi","summary"', 77)
         call expect_csv_record_count(csv_text, 'summary', 1, 78)
         call expect_csv_record_count(csv_text, 'metadata', 1, 79)
         call expect_csv_record_count(csv_text, 'rank', 2, 80)
         call expect_csv_record_count(csv_text, 'entry', 2, 81)
         call expect_csv_record_field(csv_text, 'summary', '', 'num_ranks', '2', 82)
         call expect_csv_record_field(csv_text, 'summary', '', 'num_entries', '2', 83)
         call expect_csv_real_record_field(csv_text, 'summary', '', 'min_rank_summary_window_time', 25.0_wp, 84)
         call expect_csv_real_record_field(csv_text, 'summary', '', 'avg_rank_summary_window_time', 30.0_wp, 85)
         call expect_csv_real_record_field(csv_text, 'summary', '', 'max_rank_summary_window_time', 35.0_wp, 86)
         call expect_csv_record_field(csv_text, 'metadata', 'Case', 'value', 'strict hybrid', 87)
         call expect_csv_record_field(csv_text, 'rank', '0', 'sum_lane_root_inclusive_time', &
                                      real_csv_text(22.0_wp), 88)
         call expect_csv_record_field(csv_text, 'rank', '1', 'sum_lane_root_inclusive_time', &
                                      real_csv_text(42.0_wp), 89)
         call expect_csv_record_field(csv_text, 'rank', '0', 'observed_participating_lane_count', '2', 90)
         call expect_csv_record_field(csv_text, 'rank', '1', 'configured_lane_capacity', '3', 91)
         call expect_csv_record_field(csv_text, 'entry', 'root', 'execution_domain', &
                                      'openmp_level1_team', 92)
         call expect_csv_record_field(csv_text, 'entry', 'root', 'eligible_rank_lane_sample_count', '4', 93)
         call expect_csv_record_field(csv_text, 'entry', 'root', 'participating_rank_lane_sample_count', '4', 94)
         call expect_csv_real_record_field(csv_text, 'entry', 'root', &
                                           'sum_participating_lane_self_time', 43.0_wp, 95)
         call expect_csv_real_record_field(csv_text, 'entry', 'root', &
                                           'max_participating_lane_inclusive_time', 22.0_wp, 96)
         call expect_csv_record_field(csv_text, 'entry', 'root', 'min_participating_lane_call_count', '1', 97)
         call expect_csv_record_field(csv_text, 'entry', 'root', 'max_participating_lane_call_count', '1', 98)
         call expect_csv_record_field(csv_text, 'entry', 'child', 'parent_id', &
                                      int_csv_text(summary%entries(root_idx)%node_id), 99)
      end if

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 100)
      if (rank == 0) then
         call delete_if_exists(report_path)
         call delete_if_exists(csv_path)
      end if
   end subroutine check_strict_hybrid_identical_participation

   subroutine check_sparse_hybrid_rank_lane_participation(rank)
      integer, intent(in) :: rank
      character(len=*), parameter :: csv_path = 'mpi_openmp_union_summary.csv'
      character(len=*), parameter :: report_path = 'mpi_openmp_union_summary.txt'
      type(ftimer_metadata_t) :: metadata(1)
      type(ftimer_mpi_openmp_summary_t) :: strict_summary
      type(ftimer_mpi_openmp_union_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      character(len=:), allocatable :: csv_text
      character(len=:), allocatable :: report_text
      integer :: all_id
      integer :: all_idx
      integer :: child_id
      integer :: child_rank0_idx
      integer :: child_rank1_idx
      integer :: ierr
      integer :: lane_sparse_id
      integer :: lane_sparse_idx
      integer :: parent_id
      integer :: rank0_parent_id
      integer :: rank0_parent_idx
      integer :: rank1_parent_id
      integer :: rank1_parent_idx
      integer :: rank0_only_id
      integer :: rank0_only_idx

      if (rank == 0) then
         call delete_if_exists(report_path)
         call delete_if_exists(csv_path)
      end if
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 2000

      config%max_lanes = 3
      config%max_worker_diagnostics = 4
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2001)

      fake_lane_time(0) = 2000.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2002)

      call timer%register_timer('all_worker_sparse', all_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2003)
      call timer%register_timer('rank0_only_sparse', rank0_only_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2004)
      call timer%register_timer('lane0_only_sparse', lane_sparse_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2005)
      call timer%register_timer('rank0_sparse_parent', rank0_parent_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2006)
      call timer%register_timer('rank1_sparse_parent', rank1_parent_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2007)
      call timer%register_timer('shared_sparse_child', child_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2008)

      fake_lane_time(0) = 2010.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2009)
!$omp parallel num_threads(2) default(shared) private(ierr, parent_id)
      fake_lane_time(1 + omp_get_thread_num()) = 0.0_wp
      call timer%start_id(all_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 2010
      fake_lane_time(1 + omp_get_thread_num()) = all_worker_duration(rank, omp_get_thread_num())
      call timer%stop_id(all_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 2011

      if (rank == 0) then
         fake_lane_time(1 + omp_get_thread_num()) = 20.0_wp
         call timer%start_id(rank0_only_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 2012
         fake_lane_time(1 + omp_get_thread_num()) = 20.0_wp + rank0_only_duration(omp_get_thread_num())
         call timer%stop_id(rank0_only_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 2013
      end if

      if (omp_get_thread_num() == 0) then
         fake_lane_time(1 + omp_get_thread_num()) = 40.0_wp
         call timer%start_id(lane_sparse_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 2014
         fake_lane_time(1 + omp_get_thread_num()) = 40.0_wp + merge(4.0_wp, 5.0_wp, rank == 0)
         call timer%stop_id(lane_sparse_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 2015
      end if

      if (rank == 0) then
         parent_id = rank0_parent_id
      else
         parent_id = rank1_parent_id
      end if
      fake_lane_time(1 + omp_get_thread_num()) = 60.0_wp
      call timer%start_id(parent_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 2016
      fake_lane_time(1 + omp_get_thread_num()) = 61.0_wp
      call timer%start_id(child_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 2017
      fake_lane_time(1 + omp_get_thread_num()) = 61.0_wp + mixed_child_duration(rank, omp_get_thread_num())
      call timer%stop_id(child_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 2018
      fake_lane_time(1 + omp_get_thread_num()) = 60.0_wp + mixed_parent_duration(rank, omp_get_thread_num())
      call timer%stop_id(parent_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 2019
!$omp end parallel

      fake_lane_time(0) = merge(2025.0_wp, 2030.0_wp, rank == 0)
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2020)

      call timer%mpi_openmp_summary(strict_summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_MPI_INCON, 2021)
      call expect_int(strict_summary%num_entries, 0, 2022)

      fake_lane_time(0) = merge(2035.0_wp, 2045.0_wp, rank == 0)
      call timer%mpi_openmp_union_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2023)
      call expect_int(summary%num_ranks, 2, 2024)
      call expect_int(summary%num_entries, 7, 2025)
      call expect_int(size(summary%ranks), 2, 2026)
      call expect_int(summary%ranks(1)%rank, 0, 2027)
      call expect_int(summary%ranks(2)%rank, 1, 2028)

      all_idx = find_union_entry(summary, 'all_worker_sparse', 0)
      rank0_only_idx = find_union_entry(summary, 'rank0_only_sparse', 0)
      lane_sparse_idx = find_union_entry(summary, 'lane0_only_sparse', 0)
      rank0_parent_idx = find_union_entry(summary, 'rank0_sparse_parent', 0)
      rank1_parent_idx = find_union_entry(summary, 'rank1_sparse_parent', 0)
      if (all_idx <= 0) error stop 2029
      if (rank0_only_idx <= 0) error stop 2030
      if (lane_sparse_idx <= 0) error stop 2031
      if (rank0_parent_idx <= 0) error stop 2032
      if (rank1_parent_idx <= 0) error stop 2033
      child_rank0_idx = find_union_entry(summary, 'shared_sparse_child', &
                                         summary%entries(rank0_parent_idx)%node_id)
      child_rank1_idx = find_union_entry(summary, 'shared_sparse_child', &
                                         summary%entries(rank1_parent_idx)%node_id)
      if (child_rank0_idx <= 0) error stop 2034
      if (child_rank1_idx <= 0) error stop 2035
      if (summary%entries(child_rank0_idx)%node_id == summary%entries(child_rank1_idx)%node_id) &
         error stop 2036

      call expect_union_entry(summary, all_idx, rank_count=2, missing_ranks=0, eligible_samples=4, &
                              participating_samples=4, missing_samples=0, sum_inclusive=17.0_wp, &
                              sum_self=17.0_wp, min_inclusive=2.0_wp, avg_inclusive=4.25_wp, &
                              max_inclusive=7.0_wp, min_calls=1_int64, avg_calls=1.0_wp, &
                              max_calls=1_int64, stop_code=2037)
      call expect_union_entry(summary, rank0_only_idx, rank_count=1, missing_ranks=1, eligible_samples=2, &
                              participating_samples=2, missing_samples=0, sum_inclusive=5.0_wp, &
                              sum_self=5.0_wp, min_inclusive=2.0_wp, avg_inclusive=2.5_wp, &
                              max_inclusive=3.0_wp, min_calls=1_int64, avg_calls=1.0_wp, &
                              max_calls=1_int64, stop_code=2057)
      call expect_union_entry(summary, lane_sparse_idx, rank_count=2, missing_ranks=0, eligible_samples=4, &
                              participating_samples=2, missing_samples=2, sum_inclusive=9.0_wp, &
                              sum_self=9.0_wp, min_inclusive=4.0_wp, avg_inclusive=4.5_wp, &
                              max_inclusive=5.0_wp, min_calls=1_int64, avg_calls=1.0_wp, &
                              max_calls=1_int64, stop_code=2077)
      call expect_union_entry(summary, rank0_parent_idx, rank_count=1, missing_ranks=1, eligible_samples=2, &
                              participating_samples=2, missing_samples=0, sum_inclusive=22.0_wp, &
                              sum_self=15.0_wp, min_inclusive=10.0_wp, avg_inclusive=11.0_wp, &
                              max_inclusive=12.0_wp, min_calls=1_int64, avg_calls=1.0_wp, &
                              max_calls=1_int64, stop_code=2097)
      call expect_union_entry(summary, child_rank0_idx, rank_count=1, missing_ranks=1, eligible_samples=2, &
                              participating_samples=2, missing_samples=0, sum_inclusive=7.0_wp, &
                              sum_self=7.0_wp, min_inclusive=3.0_wp, avg_inclusive=3.5_wp, &
                              max_inclusive=4.0_wp, min_calls=1_int64, avg_calls=1.0_wp, &
                              max_calls=1_int64, stop_code=2117)
      call expect_union_entry(summary, rank1_parent_idx, rank_count=1, missing_ranks=1, eligible_samples=2, &
                              participating_samples=2, missing_samples=0, sum_inclusive=30.0_wp, &
                              sum_self=19.0_wp, min_inclusive=14.0_wp, avg_inclusive=15.0_wp, &
                              max_inclusive=16.0_wp, min_calls=1_int64, avg_calls=1.0_wp, &
                              max_calls=1_int64, stop_code=2137)
      call expect_union_entry(summary, child_rank1_idx, rank_count=1, missing_ranks=1, eligible_samples=2, &
                              participating_samples=2, missing_samples=0, sum_inclusive=11.0_wp, &
                              sum_self=11.0_wp, min_inclusive=5.0_wp, avg_inclusive=5.5_wp, &
                              max_inclusive=6.0_wp, min_calls=1_int64, avg_calls=1.0_wp, &
                              max_calls=1_int64, stop_code=2157)

      metadata(1)%key = 'Case'
      metadata(1)%value = 'sparse hybrid'
      call timer%write_mpi_openmp_union_summary(report_path, metadata=metadata, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2177)
      call timer%write_mpi_openmp_union_summary_csv(csv_path, metadata=metadata, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2178)
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 2179

      if (rank == 0) then
         report_text = read_file_text(report_path)
         call expect_contains(report_text, 'Sparse MPI+OpenMP union summary', 2180)
         call expect_contains(report_text, 'Missing ranks', 2181)
         call expect_contains(report_text, 'Missing samples', 2182)
         call expect_contains(report_text, 'rank0_only_sparse', 2183)
         call expect_contains(report_text, 'lane0_only_sparse', 2184)
         call expect_contains(report_text, 'sparse hybrid', 2185)

         csv_text = read_file_text(csv_path)
         call expect_contains(csv_text, 'mpi_openmp_union', 2186)
         call expect_contains(csv_text, 'missing_rank_count', 2187)
         call expect_contains(csv_text, 'missing_rank_lane_sample_count', 2188)
         call expect_not_contains(csv_text, '"1","mpi_openmp","entry"', 2189)
         call expect_csv_record_count(csv_text, 'summary', 1, 2190)
         call expect_csv_record_count(csv_text, 'metadata', 1, 2191)
         call expect_csv_record_count(csv_text, 'rank', 2, 2192)
         call expect_csv_record_count(csv_text, 'entry', 7, 2193)
         call expect_csv_record_field(csv_text, 'metadata', 'Case', 'value', 'sparse hybrid', 2194)
         call expect_csv_record_field(csv_text, 'entry', 'rank0_only_sparse', 'participating_rank_count', '1', 2195)
         call expect_csv_record_field(csv_text, 'entry', 'rank0_only_sparse', 'missing_rank_count', '1', 2196)
         call expect_csv_record_field(csv_text, 'entry', 'lane0_only_sparse', &
                                      'missing_rank_lane_sample_count', '2', 2197)
         call expect_csv_entry_field(csv_text, 'shared_sparse_child', &
                                     int_csv_text(summary%entries(rank0_parent_idx)%node_id), &
                                     'parent_id', int_csv_text(summary%entries(rank0_parent_idx)%node_id), 2198)
         call expect_csv_entry_field(csv_text, 'shared_sparse_child', &
                                     int_csv_text(summary%entries(rank1_parent_idx)%node_id), &
                                     'parent_id', int_csv_text(summary%entries(rank1_parent_idx)%node_id), 2199)
      end if

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2200)
      if (rank == 0) then
         call delete_if_exists(report_path)
         call delete_if_exists(csv_path)
      end if
   end subroutine check_sparse_hybrid_rank_lane_participation

   subroutine check_sparse_hybrid_active_lane_failure(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_union_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: active_id
      integer :: ierr

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2210)
      fake_lane_time(0) = 2100.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2211)
      call timer%register_timer('sparse_active', active_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2212)

      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2213)
!$omp parallel num_threads(2) default(shared) private(ierr)
      if ((rank == 0) .and. (omp_get_thread_num() == 0)) then
         fake_lane_time(1) = 0.0_wp
         call timer%start_id(active_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 2214
      end if
!$omp end parallel

      call timer%mpi_openmp_union_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 2215)
      call expect_int(summary%num_entries, 0, 2216)

!$omp parallel num_threads(2) default(shared) private(ierr)
      if ((rank == 0) .and. (omp_get_thread_num() == 0)) then
         fake_lane_time(1) = 2.0_wp
         call timer%stop_id(active_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 2217
      end if
!$omp end parallel
      fake_lane_time(0) = 2105.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2218)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 2219)
   end subroutine check_sparse_hybrid_active_lane_failure

   subroutine check_strict_hybrid_serial_lane_success(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: serial_id
      integer :: serial_idx

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 210)
      fake_lane_time(0) = 800.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 211)
      call timer%register_timer('serial_strict', serial_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 212)

      fake_lane_time(0) = merge(801.0_wp, 802.0_wp, rank == 0)
      call timer%start_id(serial_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 213)
      fake_lane_time(0) = merge(805.0_wp, 808.0_wp, rank == 0)
      call timer%stop_id(serial_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 214)

      fake_lane_time(0) = merge(810.0_wp, 812.0_wp, rank == 0)
      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 215)
      call expect_int(summary%num_entries, 1, 216)
      serial_idx = find_entry(summary, 'serial_strict', 0)
      if (serial_idx <= 0) error stop 217
      if (summary%entries(serial_idx)%execution_domain /= 'serial_lane') error stop 218
      call expect_entry(summary, serial_idx, rank_count=2, eligible_samples=2, &
                        participating_samples=2, missing_samples=0, sum_inclusive=10.0_wp, &
                        sum_self=10.0_wp, min_inclusive=4.0_wp, avg_inclusive=5.0_wp, &
                        max_inclusive=6.0_wp, inclusive_imbalance=6.0_wp/5.0_wp, &
                        min_self=4.0_wp, avg_self=5.0_wp, max_self=6.0_wp, &
                        self_imbalance=6.0_wp/5.0_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=219)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 238)
   end subroutine check_strict_hybrid_serial_lane_success

   subroutine check_strict_hybrid_registration_order_independent(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: child_id
      integer :: child_idx
      integer :: ierr
      integer :: parent_id
      integer :: parent_idx

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 390)
      fake_lane_time(0) = 1300.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 391)

      if (rank == 0) then
         call timer%register_timer('order_parent', parent_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 392)
         call timer%register_timer('order_child', child_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 393)
      else
         call timer%register_timer('order_child', child_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 392)
         call timer%register_timer('order_parent', parent_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 393)
      end if

      fake_lane_time(0) = 1310.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 394)
!$omp parallel num_threads(2) default(shared) private(ierr)
      if (omp_get_thread_num() == 0) then
         fake_lane_time(1) = 0.0_wp
         call timer%start_id(parent_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 395
         fake_lane_time(1) = 2.0_wp
         call timer%start_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 396
         fake_lane_time(1) = 5.0_wp
         call timer%stop_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 397
         fake_lane_time(1) = 10.0_wp
         call timer%stop_id(parent_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 398
      else
         fake_lane_time(2) = 0.0_wp
         call timer%start_id(parent_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 399
         fake_lane_time(2) = 3.0_wp
         call timer%start_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 400
         fake_lane_time(2) = 7.0_wp
         call timer%stop_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 401
         fake_lane_time(2) = 12.0_wp
         call timer%stop_id(parent_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 402
      end if
!$omp end parallel
      fake_lane_time(0) = 1320.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 403)

      fake_lane_time(0) = 1325.0_wp
      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 404)
      call expect_int(summary%num_entries, 2, 405)
      parent_idx = find_entry(summary, 'order_parent', 0)
      if (parent_idx <= 0) error stop 406
      child_idx = find_entry(summary, 'order_child', summary%entries(parent_idx)%node_id)
      if (child_idx <= 0) error stop 407

      call expect_entry(summary, parent_idx, rank_count=2, eligible_samples=4, &
                        participating_samples=4, missing_samples=0, sum_inclusive=44.0_wp, &
                        sum_self=30.0_wp, min_inclusive=10.0_wp, avg_inclusive=11.0_wp, &
                        max_inclusive=12.0_wp, inclusive_imbalance=12.0_wp/11.0_wp, &
                        min_self=7.0_wp, avg_self=7.5_wp, max_self=8.0_wp, &
                        self_imbalance=8.0_wp/7.5_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=408)
      call expect_entry(summary, child_idx, rank_count=2, eligible_samples=4, &
                        participating_samples=4, missing_samples=0, sum_inclusive=14.0_wp, &
                        sum_self=14.0_wp, min_inclusive=3.0_wp, avg_inclusive=3.5_wp, &
                        max_inclusive=4.0_wp, inclusive_imbalance=4.0_wp/3.5_wp, &
                        min_self=3.0_wp, avg_self=3.5_wp, max_self=4.0_wp, &
                        self_imbalance=4.0_wp/3.5_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=427)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 446)
   end subroutine check_strict_hybrid_registration_order_independent

   subroutine check_strict_hybrid_serial_lane_active_failure(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer
      integer :: active_id
      integer :: ierr

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 240)
      fake_lane_time(0) = 900.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 241)
      call timer%register_timer('serial_active', active_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 242)

      fake_lane_time(0) = 901.0_wp
      call timer%start_id(active_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 243)
      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 244)
      call expect_int(summary%num_entries, 0, 245)
      call timer%mpi_openmp_summary(summary)

      fake_lane_time(0) = 902.0_wp
      call timer%stop_id(active_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 246)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 247)
   end subroutine check_strict_hybrid_serial_lane_active_failure

   subroutine check_strict_hybrid_null_comm_failure(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer
      integer :: ierr

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_NULL, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1230)
      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 1231)
      call expect_int(summary%num_entries, 0, 1232)
      if (rank == 0) call timer%mpi_openmp_summary(summary)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1233)
   end subroutine check_strict_hybrid_null_comm_failure

   subroutine check_strict_hybrid_post_finalize_subcomm_failure(rank)
      integer, intent(in) :: rank
      type(MPI_Comm) :: subcomm
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer
      integer :: ierr

      config%max_lanes = 3
      call MPI_Comm_split(MPI_COMM_WORLD, 0, rank, subcomm, ierr)
      if (ierr /= MPI_SUCCESS) error stop 1234
      call timer%init(config=config, comm=subcomm, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1235)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 1236)
      call MPI_Comm_free(subcomm, ierr)
      if (ierr /= MPI_SUCCESS) error stop 1237

      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_INIT, 1238)
      call expect_int(summary%num_entries, 0, 1239)
   end subroutine check_strict_hybrid_post_finalize_subcomm_failure

   subroutine check_strict_hybrid_uninitialized_rank_failure(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer
      integer :: ierr

      config%max_lanes = 3
      if (rank == 1) then
         call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 1240)
         fake_lane_time(0) = 180.0_wp
         call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 1241)
      end if

      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 1242

      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_NOT_INIT, 1243)
      call expect_int(summary%num_entries, 0, 1244)

      if (rank == 1) then
         call timer%finalize(ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 1245)
      end if
   end subroutine check_strict_hybrid_uninitialized_rank_failure

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
      call timer%mpi_openmp_summary(summary)

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
      call timer%mpi_openmp_summary(summary)
      fake_lane_time(0) = 252.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 115)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 116)
   end subroutine check_strict_hybrid_open_region_failure

   subroutine check_strict_hybrid_parallel_entry_local_failure(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: worker_ierr

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 117)
      fake_lane_time(0) = 275.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 118)

      worker_ierr = -999
!$omp parallel num_threads(2) default(shared)
      if (omp_get_thread_num() == 0) call timer%mpi_openmp_summary(summary, ierr=worker_ierr)
!$omp end parallel
      ierr = worker_ierr
      call expect_status(ierr, FTIMER_ERR_ACTIVE, 120)
      call expect_int(summary%num_entries, 0, 121)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 122)
   end subroutine check_strict_hybrid_parallel_entry_local_failure

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
      call timer%mpi_openmp_summary(summary)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 86)
   end subroutine check_strict_hybrid_descriptor_mismatch

   subroutine check_strict_hybrid_same_name_contexts(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: parent_a_id
      integer :: parent_a_idx
      integer :: parent_b_id
      integer :: parent_b_idx
      integer :: shared_id
      integer :: shared_under_a_idx
      integer :: shared_under_b_idx

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 260)
      fake_lane_time(0) = 1000.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 261)
      call timer%register_timer('parent_a', parent_a_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 262)
      call timer%register_timer('parent_b', parent_b_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 263)
      call timer%register_timer('shared', shared_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 264)

      fake_lane_time(0) = 1001.0_wp
      call timer%start_id(parent_a_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 265)
      fake_lane_time(0) = 1002.0_wp
      call timer%start_id(shared_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 266)
      fake_lane_time(0) = merge(1004.0_wp, 1005.0_wp, rank == 0)
      call timer%stop_id(shared_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 267)
      fake_lane_time(0) = merge(1005.0_wp, 1007.0_wp, rank == 0)
      call timer%stop_id(parent_a_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 268)

      fake_lane_time(0) = 1010.0_wp
      call timer%start_id(parent_b_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 269)
      fake_lane_time(0) = 1011.0_wp
      call timer%start_id(shared_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 270)
      fake_lane_time(0) = merge(1015.0_wp, 1017.0_wp, rank == 0)
      call timer%stop_id(shared_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 271)
      fake_lane_time(0) = merge(1018.0_wp, 1020.0_wp, rank == 0)
      call timer%stop_id(parent_b_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 272)

      fake_lane_time(0) = merge(1025.0_wp, 1028.0_wp, rank == 0)
      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 273)
      call expect_int(summary%num_entries, 4, 274)

      parent_a_idx = find_entry(summary, 'parent_a', 0)
      parent_b_idx = find_entry(summary, 'parent_b', 0)
      if (parent_a_idx <= 0) error stop 275
      if (parent_b_idx <= 0) error stop 276
      shared_under_a_idx = find_entry(summary, 'shared', summary%entries(parent_a_idx)%node_id)
      shared_under_b_idx = find_entry(summary, 'shared', summary%entries(parent_b_idx)%node_id)
      if (shared_under_a_idx <= 0) error stop 277
      if (shared_under_b_idx <= 0) error stop 278
      if (summary%entries(shared_under_a_idx)%node_id == &
          summary%entries(shared_under_b_idx)%node_id) error stop 279
      if (summary%entries(shared_under_a_idx)%execution_domain /= 'serial_lane') error stop 280
      if (summary%entries(shared_under_b_idx)%execution_domain /= 'serial_lane') error stop 281

      call expect_entry(summary, shared_under_a_idx, rank_count=2, eligible_samples=2, &
                        participating_samples=2, missing_samples=0, sum_inclusive=5.0_wp, &
                        sum_self=5.0_wp, min_inclusive=2.0_wp, avg_inclusive=2.5_wp, &
                        max_inclusive=3.0_wp, inclusive_imbalance=3.0_wp/2.5_wp, &
                        min_self=2.0_wp, avg_self=2.5_wp, max_self=3.0_wp, &
                        self_imbalance=3.0_wp/2.5_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=282)
      call expect_entry(summary, shared_under_b_idx, rank_count=2, eligible_samples=2, &
                        participating_samples=2, missing_samples=0, sum_inclusive=10.0_wp, &
                        sum_self=10.0_wp, min_inclusive=4.0_wp, avg_inclusive=5.0_wp, &
                        max_inclusive=6.0_wp, inclusive_imbalance=6.0_wp/5.0_wp, &
                        min_self=4.0_wp, avg_self=5.0_wp, max_self=6.0_wp, &
                        self_imbalance=6.0_wp/5.0_wp, min_calls=1_int64, &
                        avg_calls=1.0_wp, max_calls=1_int64, stop_code=301)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 320)
   end subroutine check_strict_hybrid_same_name_contexts

   subroutine check_strict_hybrid_context_path_mismatch(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: parent_a_id
      integer :: parent_b_id
      integer :: parent_id
      integer :: shared_id

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 330)
      fake_lane_time(0) = 1100.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 331)
      call timer%register_timer('rank0_parent', parent_a_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 332)
      call timer%register_timer('rank1_parent', parent_b_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 333)
      call timer%register_timer('shared_leaf', shared_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 334)

      parent_id = merge(parent_a_id, parent_b_id, rank == 0)
      fake_lane_time(0) = 1101.0_wp
      call timer%start_id(parent_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 335)
      fake_lane_time(0) = 1102.0_wp
      call timer%start_id(shared_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 336)
      fake_lane_time(0) = 1104.0_wp
      call timer%stop_id(shared_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 337)
      fake_lane_time(0) = 1105.0_wp
      call timer%stop_id(parent_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 338)

      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_MPI_INCON, 339)
      call expect_int(summary%num_entries, 0, 340)
      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 341)
   end subroutine check_strict_hybrid_context_path_mismatch

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
      call timer%mpi_openmp_summary(summary)
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

   subroutine check_strict_hybrid_varied_call_counts(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer
      integer :: call_idx
      integer :: ierr
      integer :: repeats
      integer :: timer_id
      integer :: varied_idx

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 350)
      fake_lane_time(0) = 1200.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 351)
      call timer%register_timer('varied_calls', timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 352)

      repeats = merge(2, 1, rank == 0)
      do call_idx = 1, repeats
         fake_lane_time(0) = 1200.0_wp + real(call_idx, wp)*10.0_wp
         call timer%start_id(timer_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 353)
         fake_lane_time(0) = fake_lane_time(0) + merge(3.0_wp, 2.0_wp, call_idx == 2)
         call timer%stop_id(timer_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 354)
      end do

      fake_lane_time(0) = 1230.0_wp
      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 355)
      call expect_int(summary%num_entries, 1, 356)
      varied_idx = find_entry(summary, 'varied_calls', 0)
      if (varied_idx <= 0) error stop 357
      call expect_entry(summary, varied_idx, rank_count=2, eligible_samples=2, &
                        participating_samples=2, missing_samples=0, sum_inclusive=7.0_wp, &
                        sum_self=7.0_wp, min_inclusive=2.0_wp, avg_inclusive=3.5_wp, &
                        max_inclusive=5.0_wp, inclusive_imbalance=5.0_wp/3.5_wp, &
                        min_self=2.0_wp, avg_self=3.5_wp, max_self=5.0_wp, &
                        self_imbalance=5.0_wp/3.5_wp, min_calls=1_int64, &
                        avg_calls=1.5_wp, max_calls=2_int64, stop_code=358)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 377)
   end subroutine check_strict_hybrid_varied_call_counts

   subroutine check_strict_hybrid_worker_varied_call_counts(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: call_idx
      integer :: ierr
      integer :: lane_id
      integer :: repeats
      integer :: timer_id
      integer :: varied_idx
      real(wp) :: duration
      real(wp) :: total_time

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 450)
      fake_lane_time(0) = 1400.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 451)
      call timer%register_timer('worker_varied_calls', timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 452)

      fake_lane_time(0) = 1410.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 453)
!$omp parallel num_threads(2) default(shared) private(call_idx, duration, ierr, lane_id, repeats, total_time)
      lane_id = 1 + omp_get_thread_num()
      repeats = 1 + omp_get_thread_num() + 2*rank
      if (rank == 0) then
         total_time = merge(4.0_wp, 0.5_wp, omp_get_thread_num() == 0)
      else
         total_time = merge(6.0_wp, 2.0_wp, omp_get_thread_num() == 0)
      end if
      duration = total_time/real(repeats, wp)
      do call_idx = 1, repeats
         fake_lane_time(lane_id) = 10.0_wp*real(call_idx, wp)
         call timer%start_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 454
         fake_lane_time(lane_id) = fake_lane_time(lane_id) + duration
         call timer%stop_id(timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 455
      end do
!$omp end parallel
      fake_lane_time(0) = 1420.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 456)

      fake_lane_time(0) = 1425.0_wp
      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 457)
      call expect_int(summary%num_entries, 1, 458)
      varied_idx = find_entry(summary, 'worker_varied_calls', 0)
      if (varied_idx <= 0) error stop 459
      if (summary%entries(varied_idx)%execution_domain /= 'openmp_level1_team') error stop 460
      call expect_entry(summary, varied_idx, rank_count=2, eligible_samples=4, &
                        participating_samples=4, missing_samples=0, sum_inclusive=12.5_wp, &
                        sum_self=12.5_wp, min_inclusive=0.5_wp, avg_inclusive=3.125_wp, &
                        max_inclusive=6.0_wp, inclusive_imbalance=6.0_wp/3.125_wp, &
                        min_self=0.5_wp, avg_self=3.125_wp, max_self=6.0_wp, &
                        self_imbalance=6.0_wp/3.125_wp, min_calls=1_int64, &
                        avg_calls=2.5_wp, max_calls=4_int64, stop_code=461)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 480)
   end subroutine check_strict_hybrid_worker_varied_call_counts

   subroutine check_strict_hybrid_worker_context_call_counts(rank)
      integer, intent(in) :: rank
      character(len=*), parameter :: csv_path = 'mpi_openmp_summary_worker_contexts.csv'
      character(len=*), parameter :: report_path = 'mpi_openmp_summary_worker_contexts.txt'
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      character(len=:), allocatable :: csv_text
      character(len=:), allocatable :: report_text
      integer :: call_idx
      integer :: child_id
      integer :: child_under_a_idx
      integer :: child_under_b_idx
      integer :: ierr
      integer :: lane_id
      integer :: parent_a_id
      integer :: parent_a_idx
      integer :: parent_b_id
      integer :: parent_b_idx
      integer :: repeats_a
      integer :: repeats_b
      real(wp) :: duration
      real(wp) :: total_time_a
      real(wp) :: total_time_b

      if (rank == 0) then
         call delete_if_exists(report_path)
         call delete_if_exists(csv_path)
      end if
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 649

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 650)
      fake_lane_time(0) = 1600.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 651)
      call timer%register_timer('worker_parent_a_ctx', parent_a_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 652)
      call timer%register_timer('worker_parent_b_ctx', parent_b_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 653)
      call timer%register_timer('worker_shared_ctx', child_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 654)

      fake_lane_time(0) = 1610.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 655)
!$omp parallel num_threads(2) default(shared) private(call_idx, duration, ierr, lane_id, &
!$omp& repeats_a, repeats_b, total_time_a, total_time_b)
      lane_id = 1 + omp_get_thread_num()
      repeats_a = 1 + omp_get_thread_num() + 2*rank
      if (rank == 0) then
         total_time_a = merge(4.0_wp, 0.5_wp, omp_get_thread_num() == 0)
      else
         total_time_a = merge(6.0_wp, 2.0_wp, omp_get_thread_num() == 0)
      end if
      duration = total_time_a/real(repeats_a, wp)
      fake_lane_time(lane_id) = 100.0_wp
      call timer%start_id(parent_a_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 656
      do call_idx = 1, repeats_a
         fake_lane_time(lane_id) = 100.0_wp + 10.0_wp*real(call_idx, wp)
         call timer%start_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 657
         fake_lane_time(lane_id) = fake_lane_time(lane_id) + duration
         call timer%stop_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 658
      end do
      call timer%stop_id(parent_a_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 659

      repeats_b = merge(2, 5, rank == 0)
      if (rank == 0) then
         total_time_b = merge(1.0_wp, 7.0_wp, omp_get_thread_num() == 0)
      else
         total_time_b = merge(3.0_wp, 9.0_wp, omp_get_thread_num() == 0)
      end if
      duration = total_time_b/real(repeats_b, wp)
      fake_lane_time(lane_id) = 300.0_wp
      call timer%start_id(parent_b_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 660
      do call_idx = 1, repeats_b
         fake_lane_time(lane_id) = 300.0_wp + 10.0_wp*real(call_idx, wp)
         call timer%start_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 661
         fake_lane_time(lane_id) = fake_lane_time(lane_id) + duration
         call timer%stop_id(child_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 662
      end do
      call timer%stop_id(parent_b_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 663
!$omp end parallel
      fake_lane_time(0) = 1620.0_wp
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 664)

      fake_lane_time(0) = 1625.0_wp
      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 665)
      call expect_int(summary%num_entries, 4, 666)
      parent_a_idx = find_entry(summary, 'worker_parent_a_ctx', 0)
      parent_b_idx = find_entry(summary, 'worker_parent_b_ctx', 0)
      if (parent_a_idx <= 0) error stop 667
      if (parent_b_idx <= 0) error stop 668
      child_under_a_idx = find_entry(summary, 'worker_shared_ctx', summary%entries(parent_a_idx)%node_id)
      child_under_b_idx = find_entry(summary, 'worker_shared_ctx', summary%entries(parent_b_idx)%node_id)
      if (child_under_a_idx <= 0) error stop 669
      if (child_under_b_idx <= 0) error stop 670
      if (summary%entries(child_under_a_idx)%node_id == &
          summary%entries(child_under_b_idx)%node_id) error stop 671
      if (summary%entries(child_under_a_idx)%parent_id == &
          summary%entries(child_under_b_idx)%parent_id) error stop 672
      if (summary%entries(child_under_a_idx)%execution_domain /= 'openmp_level1_team') error stop 673
      if (summary%entries(child_under_b_idx)%execution_domain /= 'openmp_level1_team') error stop 674

      call expect_entry(summary, child_under_a_idx, rank_count=2, eligible_samples=4, &
                        participating_samples=4, missing_samples=0, sum_inclusive=12.5_wp, &
                        sum_self=12.5_wp, min_inclusive=0.5_wp, avg_inclusive=3.125_wp, &
                        max_inclusive=6.0_wp, inclusive_imbalance=6.0_wp/3.125_wp, &
                        min_self=0.5_wp, avg_self=3.125_wp, max_self=6.0_wp, &
                        self_imbalance=6.0_wp/3.125_wp, min_calls=1_int64, &
                        avg_calls=2.5_wp, max_calls=4_int64, stop_code=675)
      call expect_entry(summary, child_under_b_idx, rank_count=2, eligible_samples=4, &
                        participating_samples=4, missing_samples=0, sum_inclusive=20.0_wp, &
                        sum_self=20.0_wp, min_inclusive=1.0_wp, avg_inclusive=5.0_wp, &
                        max_inclusive=9.0_wp, inclusive_imbalance=9.0_wp/5.0_wp, &
                        min_self=1.0_wp, avg_self=5.0_wp, max_self=9.0_wp, &
                        self_imbalance=9.0_wp/5.0_wp, min_calls=2_int64, &
                        avg_calls=3.5_wp, max_calls=5_int64, stop_code=694)

      call timer%write_mpi_openmp_summary(report_path, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 714)
      call timer%write_mpi_openmp_summary_csv(csv_path, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 715)
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 716
      if (rank == 0) then
         report_text = read_file_text(report_path)
         call expect_report_entry_count(report_text, 'worker_shared_ctx', 2, 717)
         call expect_report_entry_line_by_values(report_text, 'worker_shared_ctx', 1, &
                                                 12.5_wp, 3.125_wp, 6.0_wp, 2.5_wp, 718)
         call expect_report_entry_line_by_values(report_text, 'worker_shared_ctx', 1, &
                                                 20.0_wp, 5.0_wp, 9.0_wp, 3.5_wp, 719)
         call expect_report_child_under_parent_by_values(report_text, 'worker_parent_a_ctx', &
                                                         'worker_shared_ctx', 12.5_wp, 3.125_wp, &
                                                         6.0_wp, 2.5_wp, 732)
         call expect_report_child_under_parent_by_values(report_text, 'worker_parent_b_ctx', &
                                                         'worker_shared_ctx', 20.0_wp, 5.0_wp, &
                                                         9.0_wp, 3.5_wp, 733)

         csv_text = read_file_text(csv_path)
         call expect_csv_record_count(csv_text, 'entry', 4, 720)
         call expect_csv_entry_field(csv_text, 'worker_shared_ctx', &
                                     int_csv_text(summary%entries(parent_a_idx)%node_id), &
                                     'node_id', int_csv_text(summary%entries(child_under_a_idx)%node_id), 721)
         call expect_csv_entry_field(csv_text, 'worker_shared_ctx', &
                                     int_csv_text(summary%entries(parent_a_idx)%node_id), &
                                     'depth', '1', 722)
         call expect_csv_entry_field(csv_text, 'worker_shared_ctx', &
                                     int_csv_text(summary%entries(parent_a_idx)%node_id), &
                                     'execution_domain', 'openmp_level1_team', 723)
         call expect_csv_entry_real_field(csv_text, 'worker_shared_ctx', &
                                          int_csv_text(summary%entries(parent_a_idx)%node_id), &
                                          'sum_participating_lane_inclusive_time', 12.5_wp, 724)
         call expect_csv_entry_real_field(csv_text, 'worker_shared_ctx', &
                                          int_csv_text(summary%entries(parent_a_idx)%node_id), &
                                          'avg_participating_lane_call_count', 2.5_wp, 725)
         call expect_csv_entry_field(csv_text, 'worker_shared_ctx', &
                                     int_csv_text(summary%entries(parent_b_idx)%node_id), &
                                     'node_id', int_csv_text(summary%entries(child_under_b_idx)%node_id), 726)
         call expect_csv_entry_field(csv_text, 'worker_shared_ctx', &
                                     int_csv_text(summary%entries(parent_b_idx)%node_id), &
                                     'depth', '1', 727)
         call expect_csv_entry_field(csv_text, 'worker_shared_ctx', &
                                     int_csv_text(summary%entries(parent_b_idx)%node_id), &
                                     'execution_domain', 'openmp_level1_team', 728)
         call expect_csv_entry_real_field(csv_text, 'worker_shared_ctx', &
                                          int_csv_text(summary%entries(parent_b_idx)%node_id), &
                                          'sum_participating_lane_inclusive_time', 20.0_wp, 729)
         call expect_csv_entry_real_field(csv_text, 'worker_shared_ctx', &
                                          int_csv_text(summary%entries(parent_b_idx)%node_id), &
                                          'avg_participating_lane_call_count', 3.5_wp, 730)
      end if

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 731)
      if (rank == 0) then
         call delete_if_exists(report_path)
         call delete_if_exists(csv_path)
      end if
   end subroutine check_strict_hybrid_worker_context_call_counts

   subroutine check_strict_hybrid_worker_diagnostic_ierr_preflight(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: timer_id

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 740)
      fake_lane_time(0) = 1700.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 741)
      if (rank == 0) then
         call timer%register_timer('diagnostic_rank0_path', timer_id, ierr=ierr)
      else
         call timer%register_timer('diagnostic_rank1_path', timer_id, ierr=ierr)
      end if
      call expect_status(ierr, FTIMER_SUCCESS, 742)
      call run_all_worker_lanes(timer, region, timer_id, 1.0_wp, 2.0_wp, 743)

!$omp parallel num_threads(2) default(shared)
      if ((rank == 1) .and. (omp_get_thread_num() == 0)) call timer%start_id(-999)
!$omp end parallel

      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_UNKNOWN, 745)
      call expect_int(summary%num_entries, 0, 746)

      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_MPI_INCON, 747)
      call expect_int(summary%num_entries, 0, 748)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 749)
   end subroutine check_strict_hybrid_worker_diagnostic_ierr_preflight

   subroutine check_strict_hybrid_worker_diagnostic_no_ierr_failure(rank)
      integer, intent(in) :: rank
      character(len=*), parameter :: csv_path = 'mpi_openmp_summary_worker_diagnostic.csv'
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: timer_id
      logical :: exists

      if (rank == 0) call delete_if_exists(csv_path)
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 490

      config%max_lanes = 3
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 491)
      fake_lane_time(0) = 1500.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 492)
      call timer%register_timer('worker_diagnostic', timer_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 493)
      call run_all_worker_lanes(timer, region, timer_id, 1.0_wp, 2.0_wp, 494)

!$omp parallel num_threads(2) default(shared)
      if ((rank == 1) .and. (omp_get_thread_num() == 0)) call timer%start_id(-999)
!$omp end parallel

      call timer%write_mpi_openmp_summary_csv(csv_path)
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 496
      if (rank == 0) then
         inquire (file=csv_path, exist=exists)
         if (exists) error stop 497
      end if

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 498)
      if (rank == 0) call delete_if_exists(csv_path)
   end subroutine check_strict_hybrid_worker_diagnostic_no_ierr_failure

   subroutine check_strict_hybrid_csv_append_validation(rank)
      integer, intent(in) :: rank
      character(len=*), parameter :: bad_record_path = 'mpi_openmp_summary_bad_record_append.csv'
      character(len=*), parameter :: bare_cr_path = 'mpi_openmp_summary_bare_cr_append.csv'
      character(len=*), parameter :: csv_path = 'mpi_openmp_summary_append.csv'
      character(len=*), parameter :: malformed_quote_path = 'mpi_openmp_summary_malformed_quote_append.csv'
      character(len=*), parameter :: no_newline_path = 'mpi_openmp_summary_no_newline_append.csv'
      character(len=*), parameter :: unterminated_quote_path = 'mpi_openmp_summary_unterminated_quote_append.csv'
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
         call delete_if_exists(bare_cr_path)
         call delete_if_exists(malformed_quote_path)
         call delete_if_exists(no_newline_path)
         call delete_if_exists(unterminated_quote_path)
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
         call write_raw_text_file(bad_record_path, bad_text)
         bad_text = header//new_line('a')//'"1","mpi_openmp","summary",'
         call write_raw_text_file(no_newline_path, bad_text)
         bad_text = header//new_line('a')// &
                    replace_first(csv_line_at(csv_text, 2), '"summary"', '"invalid"')//new_line('a')
         call write_raw_text_file(unknown_record_path, bad_text)
         bad_text = header//new_line('a')//'"1","mpi_openmp","summary'//new_line('a')
         call write_raw_text_file(unterminated_quote_path, bad_text)
         bad_text = header//new_line('a')//'1"bad'//new_line('a')
         call write_raw_text_file(malformed_quote_path, bad_text)
         bad_text = header//new_line('a')//'"1","mpi_openmp","summary"'//achar(13)//'x'//new_line('a')
         call write_raw_text_file(bare_cr_path, bad_text)
         bad_text = 'format_version,summary_kind,record_type'//new_line('a')
         call write_raw_text_file(wrong_header_path, bad_text)
      end if
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 190

      call timer%write_mpi_openmp_summary_csv(bad_record_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 191)
      call timer%write_mpi_openmp_summary_csv(unknown_record_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 192)
      call timer%write_mpi_openmp_summary_csv(no_newline_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 193)
      call timer%write_mpi_openmp_summary_csv(unterminated_quote_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 194)
      call timer%write_mpi_openmp_summary_csv(malformed_quote_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 196)
      call timer%write_mpi_openmp_summary_csv(bare_cr_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 197)
      call timer%write_mpi_openmp_summary_csv(wrong_header_path, append=.true., ierr=ierr)
      call expect_status(ierr, FTIMER_ERR_IO, 198)
      call timer%write_mpi_openmp_summary_csv(bad_record_path, append=.true.)
      call timer%write_mpi_openmp_summary_csv(unknown_record_path, append=.true.)
      call timer%write_mpi_openmp_summary_csv(no_newline_path, append=.true.)
      call timer%write_mpi_openmp_summary_csv(unterminated_quote_path, append=.true.)
      call timer%write_mpi_openmp_summary_csv(malformed_quote_path, append=.true.)
      call timer%write_mpi_openmp_summary_csv(bare_cr_path, append=.true.)
      call timer%write_mpi_openmp_summary_csv(wrong_header_path, append=.true.)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 195)
      if (rank == 0) then
         call delete_if_exists(csv_path)
         call delete_if_exists(bad_record_path)
         call delete_if_exists(bare_cr_path)
         call delete_if_exists(malformed_quote_path)
         call delete_if_exists(no_newline_path)
         call delete_if_exists(unterminated_quote_path)
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

   real(wp) function all_worker_duration(rank, thread_num) result(duration)
      integer, intent(in) :: rank
      integer, intent(in) :: thread_num

      if (rank == 0) then
         duration = merge(2.0_wp, 3.0_wp, thread_num == 0)
      else
         duration = merge(5.0_wp, 7.0_wp, thread_num == 0)
      end if
   end function all_worker_duration

   real(wp) function rank0_only_duration(thread_num) result(duration)
      integer, intent(in) :: thread_num

      duration = merge(2.0_wp, 3.0_wp, thread_num == 0)
   end function rank0_only_duration

   real(wp) function mixed_parent_duration(rank, thread_num) result(duration)
      integer, intent(in) :: rank
      integer, intent(in) :: thread_num

      if (rank == 0) then
         duration = merge(10.0_wp, 12.0_wp, thread_num == 0)
      else
         duration = merge(14.0_wp, 16.0_wp, thread_num == 0)
      end if
   end function mixed_parent_duration

   real(wp) function mixed_child_duration(rank, thread_num) result(duration)
      integer, intent(in) :: rank
      integer, intent(in) :: thread_num

      if (rank == 0) then
         duration = merge(3.0_wp, 4.0_wp, thread_num == 0)
      else
         duration = merge(5.0_wp, 6.0_wp, thread_num == 0)
      end if
   end function mixed_child_duration

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

   integer function find_union_entry(summary, name, parent_id) result(idx)
      type(ftimer_mpi_openmp_union_summary_t), intent(in) :: summary
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
   end function find_union_entry

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

   subroutine expect_union_entry(summary, idx, rank_count, missing_ranks, eligible_samples, &
                                 participating_samples, missing_samples, sum_inclusive, sum_self, &
                                 min_inclusive, avg_inclusive, max_inclusive, min_calls, avg_calls, &
                                 max_calls, stop_code)
      type(ftimer_mpi_openmp_union_summary_t), intent(in) :: summary
      integer, intent(in) :: idx
      integer, intent(in) :: rank_count
      integer, intent(in) :: missing_ranks
      integer, intent(in) :: eligible_samples
      integer, intent(in) :: participating_samples
      integer, intent(in) :: missing_samples
      real(wp), intent(in) :: sum_inclusive
      real(wp), intent(in) :: sum_self
      real(wp), intent(in) :: min_inclusive
      real(wp), intent(in) :: avg_inclusive
      real(wp), intent(in) :: max_inclusive
      integer(int64), intent(in) :: min_calls
      real(wp), intent(in) :: avg_calls
      integer(int64), intent(in) :: max_calls
      integer, intent(in) :: stop_code

      call expect_int(summary%entries(idx)%participating_rank_count, rank_count, stop_code)
      call expect_int(summary%entries(idx)%missing_rank_count, missing_ranks, stop_code + 1)
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
      call expect_int64(summary%entries(idx)%min_participating_lane_call_count, min_calls, stop_code + 11)
      call expect_time(summary%entries(idx)%avg_participating_lane_call_count, avg_calls, stop_code + 12)
      call expect_int64(summary%entries(idx)%max_participating_lane_call_count, max_calls, stop_code + 13)
   end subroutine expect_union_entry

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

   subroutine expect_report_entry_line(report_text, name, ranks, samples, missing, &
                                       sum_inclusive, sum_self, min_inclusive, avg_inclusive, &
                                       max_inclusive, avg_calls, stop_code)
      character(len=*), intent(in) :: report_text
      character(len=*), intent(in) :: name
      integer, intent(in) :: ranks
      integer, intent(in) :: samples
      integer, intent(in) :: missing
      real(wp), intent(in) :: sum_inclusive
      real(wp), intent(in) :: sum_self
      real(wp), intent(in) :: min_inclusive
      real(wp), intent(in) :: avg_inclusive
      real(wp), intent(in) :: max_inclusive
      real(wp), intent(in) :: avg_calls
      integer, intent(in) :: stop_code
      character(len=:), allocatable :: line
      character(len=64) :: actual_domain
      character(len=64) :: actual_name
      integer :: actual_missing
      integer :: actual_ranks
      integer :: actual_samples
      integer :: io
      real(wp) :: actual_avg_calls
      real(wp) :: actual_avg_inclusive
      real(wp) :: actual_max_inclusive
      real(wp) :: actual_min_inclusive
      real(wp) :: actual_sum_inclusive
      real(wp) :: actual_sum_self

      line = find_report_entry_line(report_text, name)
      if (len(line) <= 0) error stop stop_code
      read (line, *, iostat=io) actual_name, actual_domain, actual_ranks, actual_samples, &
         actual_missing, actual_sum_inclusive, actual_sum_self, actual_min_inclusive, &
         actual_avg_inclusive, actual_max_inclusive, actual_avg_calls
      if (io /= 0) error stop stop_code
      if (trim(actual_name) /= name) error stop stop_code
      if (trim(actual_domain) /= 'openmp_level1_team') error stop stop_code
      call expect_int(actual_ranks, ranks, stop_code)
      call expect_int(actual_samples, samples, stop_code)
      call expect_int(actual_missing, missing, stop_code)
      call expect_time(actual_sum_inclusive, sum_inclusive, stop_code)
      call expect_time(actual_sum_self, sum_self, stop_code)
      call expect_time(actual_min_inclusive, min_inclusive, stop_code)
      call expect_time(actual_avg_inclusive, avg_inclusive, stop_code)
      call expect_time(actual_max_inclusive, max_inclusive, stop_code)
      call expect_time(actual_avg_calls, avg_calls, stop_code)
   end subroutine expect_report_entry_line

   subroutine expect_report_entry_count(report_text, name, expected, stop_code)
      character(len=*), intent(in) :: report_text
      character(len=*), intent(in) :: name
      integer, intent(in) :: expected
      integer, intent(in) :: stop_code
      character(len=:), allocatable :: candidate
      character(len=64) :: actual_name
      integer :: count
      integer :: io
      integer :: line_no
      integer :: max_line

      count = 0
      max_line = count_occurrences(report_text, new_line('a')) + 1
      do line_no = 1, max_line
         candidate = csv_line_at(report_text, line_no)
         actual_name = ''
         read (candidate, *, iostat=io) actual_name
         if ((io == 0) .and. (trim(actual_name) == name)) count = count + 1
      end do
      call expect_int(count, expected, stop_code)
   end subroutine expect_report_entry_count

   subroutine expect_report_entry_line_by_values(report_text, name, depth, sum_inclusive, &
                                                 avg_inclusive, max_inclusive, avg_calls, stop_code)
      character(len=*), intent(in) :: report_text
      character(len=*), intent(in) :: name
      integer, intent(in) :: depth
      real(wp), intent(in) :: sum_inclusive
      real(wp), intent(in) :: avg_inclusive
      real(wp), intent(in) :: max_inclusive
      real(wp), intent(in) :: avg_calls
      integer, intent(in) :: stop_code
      character(len=:), allocatable :: candidate
      character(len=64) :: actual_domain
      character(len=64) :: actual_name
      integer :: actual_indent
      integer :: actual_missing
      integer :: actual_ranks
      integer :: actual_samples
      integer :: found
      integer :: first_nonblank
      integer :: io
      integer :: line_no
      integer :: max_line
      real(wp) :: actual_avg_calls
      real(wp) :: actual_avg_inclusive
      real(wp) :: actual_max_inclusive
      real(wp) :: actual_min_inclusive
      real(wp) :: actual_sum_inclusive
      real(wp) :: actual_sum_self

      found = 0
      max_line = count_occurrences(report_text, new_line('a')) + 1
      do line_no = 1, max_line
         candidate = csv_line_at(report_text, line_no)
         first_nonblank = verify(candidate, ' ')
         if (first_nonblank <= 0) cycle
         actual_indent = first_nonblank - 1
         actual_name = ''
         read (candidate, *, iostat=io) actual_name, actual_domain, actual_ranks, actual_samples, &
            actual_missing, actual_sum_inclusive, actual_sum_self, actual_min_inclusive, &
            actual_avg_inclusive, actual_max_inclusive, actual_avg_calls
         if (io /= 0) cycle
         if (trim(actual_name) /= name) cycle
         if (trim(actual_domain) /= 'openmp_level1_team') cycle
         if (actual_indent /= 2*depth) cycle
         if (actual_ranks /= 2 .or. actual_samples /= 4 .or. actual_missing /= 0) cycle
         if (abs(actual_sum_inclusive - sum_inclusive) > 1.0e-9_wp) cycle
         if (abs(actual_sum_self - sum_inclusive) > 1.0e-9_wp) cycle
         if (abs(actual_avg_inclusive - avg_inclusive) > 1.0e-9_wp) cycle
         if (abs(actual_max_inclusive - max_inclusive) > 1.0e-9_wp) cycle
         if (abs(actual_avg_calls - avg_calls) > 1.0e-9_wp) cycle
         found = found + 1
      end do
      call expect_int(found, 1, stop_code)
   end subroutine expect_report_entry_line_by_values

   subroutine expect_report_child_under_parent_by_values(report_text, parent_name, child_name, &
                                                         sum_inclusive, avg_inclusive, &
                                                         max_inclusive, avg_calls, stop_code)
      character(len=*), intent(in) :: report_text
      character(len=*), intent(in) :: parent_name
      character(len=*), intent(in) :: child_name
      real(wp), intent(in) :: sum_inclusive
      real(wp), intent(in) :: avg_inclusive
      real(wp), intent(in) :: max_inclusive
      real(wp), intent(in) :: avg_calls
      integer, intent(in) :: stop_code
      character(len=:), allocatable :: candidate
      character(len=64) :: actual_domain
      character(len=64) :: actual_name
      integer :: actual_indent
      integer :: actual_missing
      integer :: actual_ranks
      integer :: actual_samples
      integer :: first_nonblank
      integer :: found
      integer :: in_parent
      integer :: io
      integer :: line_no
      integer :: max_line
      real(wp) :: actual_avg_calls
      real(wp) :: actual_avg_inclusive
      real(wp) :: actual_max_inclusive
      real(wp) :: actual_min_inclusive
      real(wp) :: actual_sum_inclusive
      real(wp) :: actual_sum_self

      found = 0
      in_parent = 0
      max_line = count_occurrences(report_text, new_line('a')) + 1
      do line_no = 1, max_line
         candidate = csv_line_at(report_text, line_no)
         first_nonblank = verify(candidate, ' ')
         if (first_nonblank <= 0) cycle
         actual_indent = first_nonblank - 1
         actual_name = ''
         read (candidate, *, iostat=io) actual_name, actual_domain, actual_ranks, actual_samples, &
            actual_missing, actual_sum_inclusive, actual_sum_self, actual_min_inclusive, &
            actual_avg_inclusive, actual_max_inclusive, actual_avg_calls
         if (io /= 0) cycle
         if (actual_indent == 0) then
            in_parent = 0
            if (trim(actual_name) == parent_name) in_parent = 1
            cycle
         end if
         if (in_parent == 0) cycle
         if (actual_indent /= 2) cycle
         if (trim(actual_name) /= child_name) cycle
         if (trim(actual_domain) /= 'openmp_level1_team') cycle
         if (actual_ranks /= 2 .or. actual_samples /= 4 .or. actual_missing /= 0) cycle
         if (abs(actual_sum_inclusive - sum_inclusive) > 1.0e-9_wp) cycle
         if (abs(actual_sum_self - sum_inclusive) > 1.0e-9_wp) cycle
         if (abs(actual_avg_inclusive - avg_inclusive) > 1.0e-9_wp) cycle
         if (abs(actual_max_inclusive - max_inclusive) > 1.0e-9_wp) cycle
         if (abs(actual_avg_calls - avg_calls) > 1.0e-9_wp) cycle
         found = found + 1
      end do
      call expect_int(found, 1, stop_code)
   end subroutine expect_report_child_under_parent_by_values

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

   function find_report_entry_line(report_text, name) result(line)
      character(len=*), intent(in) :: report_text
      character(len=*), intent(in) :: name
      character(len=:), allocatable :: candidate
      character(len=:), allocatable :: line
      character(len=64) :: first_token
      integer :: io
      integer :: line_no

      line = ''
      line_no = 1
      do
         candidate = csv_line_at(report_text, line_no)
         if ((len(candidate) <= 0) .and. (line_no > count_occurrences(report_text, new_line('a')) + 1)) exit
         first_token = ''
         read (candidate, *, iostat=io) first_token
         if ((io == 0) .and. (trim(first_token) == name)) then
            line = candidate
            return
         end if
         line_no = line_no + 1
      end do
   end function find_report_entry_line

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

   subroutine expect_csv_entry_field(csv_text, name, parent_id, column, expected, stop_code)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: name
      character(len=*), intent(in) :: parent_id
      character(len=*), intent(in) :: column
      character(len=*), intent(in) :: expected
      integer, intent(in) :: stop_code
      character(len=:), allocatable :: header
      character(len=:), allocatable :: row
      integer :: column_idx

      header = first_line(csv_text)
      row = find_csv_entry_record(csv_text, name, parent_id)
      if (len(row) <= 0) error stop stop_code
      column_idx = csv_column_index(header, column)
      if (column_idx <= 0) error stop stop_code
      if (csv_field_value(row, column_idx) /= expected) error stop stop_code
   end subroutine expect_csv_entry_field

   subroutine expect_csv_entry_real_field(csv_text, name, parent_id, column, expected, stop_code)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: name
      character(len=*), intent(in) :: parent_id
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
      row = find_csv_entry_record(csv_text, name, parent_id)
      if (len(row) <= 0) error stop stop_code
      column_idx = csv_column_index(header, column)
      if (column_idx <= 0) error stop stop_code
      field_text = csv_field_value(row, column_idx)
      read (field_text, *, iostat=io) actual
      if (io /= 0) error stop stop_code
      call expect_time(actual, expected, stop_code)
   end subroutine expect_csv_entry_real_field

   function find_csv_entry_record(csv_text, name, parent_id) result(row)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: name
      character(len=*), intent(in) :: parent_id
      character(len=:), allocatable :: row
      character(len=:), allocatable :: candidate
      character(len=:), allocatable :: header
      integer :: line_no
      integer :: name_col
      integer :: parent_id_col
      integer :: record_type_col

      row = ''
      header = first_line(csv_text)
      record_type_col = csv_column_index(header, 'record_type')
      parent_id_col = csv_column_index(header, 'parent_id')
      name_col = csv_column_index(header, 'name')
      if (record_type_col <= 0 .or. parent_id_col <= 0 .or. name_col <= 0) return
      line_no = 2
      do
         candidate = csv_line_at(csv_text, line_no)
         if (len(candidate) <= 0) exit
         if (csv_field_value(candidate, record_type_col) == 'entry' .and. &
             csv_field_value(candidate, name_col) == name .and. &
             csv_field_value(candidate, parent_id_col) == parent_id) then
            row = candidate
            return
         end if
         line_no = line_no + 1
      end do
   end function find_csv_entry_record

   function find_csv_record(csv_text, record_type, selector) result(row)
      character(len=*), intent(in) :: csv_text
      character(len=*), intent(in) :: record_type
      character(len=*), intent(in) :: selector
      character(len=:), allocatable :: row
      character(len=:), allocatable :: candidate
      character(len=:), allocatable :: header
      integer :: key_col
      integer :: line_no
      integer :: name_col
      integer :: rank_col
      integer :: record_type_col

      row = ''
      header = first_line(csv_text)
      record_type_col = csv_column_index(header, 'record_type')
      key_col = csv_column_index(header, 'key')
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
            case ('metadata')
               if ((key_col > 0) .and. (csv_field_value(candidate, key_col) == selector)) then
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

   subroutine write_raw_text_file(path, text)
      character(len=*), intent(in) :: path
      character(len=*), intent(in) :: text
      integer :: io
      integer :: unit

      open (newunit=unit, file=path, status='replace', access='stream', form='unformatted', &
            action='write', iostat=io)
      if (io /= 0) error stop 205
      write (unit, iostat=io) text
      if (io /= 0) error stop 206
      close (unit, iostat=io)
      if (io /= 0) error stop 207
   end subroutine write_raw_text_file

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
