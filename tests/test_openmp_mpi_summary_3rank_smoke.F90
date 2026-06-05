program ftimer_openmp_mpi_summary_3rank_smoke
   use, intrinsic :: iso_fortran_env, only: int64
   use ftimer_openmp, only: ftimer_mpi_openmp_summary_t, ftimer_mpi_openmp_union_summary_t, &
                            ftimer_openmp_config_t, &
                            ftimer_openmp_parallel_region_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_SUCCESS, wp
   use mpi_f08, only: MPI_Barrier, MPI_COMM_WORLD, MPI_UNDEFINED, MPI_Comm, &
                      MPI_Comm_free, MPI_Comm_rank, MPI_Comm_size, MPI_Comm_split, &
                      MPI_Finalize, MPI_Init, MPI_SUCCESS
   use omp_lib, only: omp_get_thread_num, omp_in_parallel, omp_set_dynamic, &
                      omp_set_num_threads
   implicit none

   real(wp), save :: fake_lane_time(0:3) = 0.0_wp
   integer :: ierr
   integer :: nprocs
   integer :: rank

   call MPI_Init(ierr)
   if (ierr /= MPI_SUCCESS) error stop 1

   call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
   if (ierr /= MPI_SUCCESS) error stop 2
   call MPI_Comm_size(MPI_COMM_WORLD, nprocs, ierr)
   if (ierr /= MPI_SUCCESS) error stop 3
   if (nprocs /= 3) error stop 4

   call omp_set_dynamic(.false.)
   call omp_set_num_threads(2)

   call check_three_rank_hybrid_rank_metrics(rank)
   call check_three_rank_sparse_union_participation(rank)
   call check_three_rank_explicit_subcomm(rank)

   call MPI_Finalize(ierr)
   if (ierr /= MPI_SUCCESS) error stop 5

contains

   subroutine check_three_rank_hybrid_rank_metrics(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: root_id
      integer :: root_idx

      config%max_lanes = 3
      call timer%init(config=config, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 10)

      fake_lane_time(0) = 0.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 11)
      call timer%register_timer('three_rank_root', root_id, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 12)

      fake_lane_time(0) = 1.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 13)
!$omp parallel num_threads(2) default(shared) private(ierr)
      fake_lane_time(1 + omp_get_thread_num()) = 0.0_wp
      call timer%start_id(root_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 14
      fake_lane_time(1 + omp_get_thread_num()) = &
         worker_stop_time(rank, omp_get_thread_num())
      call timer%stop_id(root_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 15
!$omp end parallel
      fake_lane_time(0) = timed_region_end_time(rank)
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 16)

      fake_lane_time(0) = summary_window_end_time(rank)
      call timer%mpi_openmp_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 17)

      call expect_int(summary%num_ranks, 3, 18)
      call expect_int(summary%num_entries, 1, 19)
      call expect_time(summary%min_rank_summary_window_time, 10.0_wp, 20)
      call expect_time(summary%avg_rank_summary_window_time, 53.0_wp/3.0_wp, 21)
      call expect_time(summary%max_rank_summary_window_time, 30.0_wp, 22)
      call expect_time(summary%rank_summary_window_imbalance, 90.0_wp/53.0_wp, 23)
      call expect_int(summary%min_rank_summary_window_time_rank, 0, 24)
      call expect_int(summary%max_rank_summary_window_time_rank, 2, 25)

      call expect_time(summary%min_rank_timed_region_envelope_time, 6.0_wp, 26)
      call expect_time(summary%avg_rank_timed_region_envelope_time, 8.0_wp, 27)
      call expect_time(summary%max_rank_timed_region_envelope_time, 12.0_wp, 28)
      call expect_time(summary%rank_timed_region_envelope_imbalance, 1.5_wp, 29)
      call expect_int(summary%min_rank_timed_region_envelope_time_rank, 0, 30)
      call expect_int(summary%max_rank_timed_region_envelope_time_rank, 2, 31)

      call expect_time(summary%min_rank_sum_lane_root_inclusive_time, 6.0_wp, 32)
      call expect_time(summary%avg_rank_sum_lane_root_inclusive_time, 16.0_wp, 33)
      call expect_time(summary%max_rank_sum_lane_root_inclusive_time, 21.0_wp, 34)
      call expect_time(summary%rank_sum_lane_root_inclusive_imbalance, 21.0_wp/16.0_wp, 35)
      call expect_int(summary%min_rank_sum_lane_root_inclusive_time_rank, 0, 36)
      call expect_int(summary%max_rank_sum_lane_root_inclusive_time_rank, 1, 37)

      call expect_time(summary%min_rank_sum_lane_self_time, 6.0_wp, 38)
      call expect_time(summary%avg_rank_sum_lane_self_time, 16.0_wp, 39)
      call expect_time(summary%max_rank_sum_lane_self_time, 21.0_wp, 40)
      call expect_time(summary%rank_sum_lane_self_imbalance, 21.0_wp/16.0_wp, 41)
      call expect_int(summary%min_rank_sum_lane_self_time_rank, 0, 42)
      call expect_int(summary%max_rank_sum_lane_self_time_rank, 1, 43)

      call expect_int(size(summary%ranks), 3, 44)
      call expect_int(summary%ranks(1)%rank, 0, 45)
      call expect_time(summary%ranks(1)%summary_window_time, 10.0_wp, 46)
      call expect_time(summary%ranks(1)%timed_region_envelope_time, 6.0_wp, 47)
      call expect_time(summary%ranks(1)%sum_lane_root_inclusive_time, 6.0_wp, 48)
      call expect_int(summary%ranks(2)%rank, 1, 49)
      call expect_time(summary%ranks(2)%summary_window_time, 13.0_wp, 50)
      call expect_time(summary%ranks(2)%timed_region_envelope_time, 6.0_wp, 51)
      call expect_time(summary%ranks(2)%sum_lane_root_inclusive_time, 21.0_wp, 52)
      call expect_int(summary%ranks(3)%rank, 2, 53)
      call expect_time(summary%ranks(3)%summary_window_time, 30.0_wp, 54)
      call expect_time(summary%ranks(3)%timed_region_envelope_time, 12.0_wp, 55)
      call expect_time(summary%ranks(3)%sum_lane_root_inclusive_time, 21.0_wp, 56)

      root_idx = find_entry(summary, 'three_rank_root', 0)
      if (root_idx <= 0) error stop 57
      if (trim(summary%entries(root_idx)%execution_domain) /= 'openmp_level1_team') &
         error stop 58
      call expect_int(summary%entries(root_idx)%participating_rank_count, 3, 59)
      call expect_int(summary%entries(root_idx)%missing_rank_count, 0, 60)
      call expect_int(summary%entries(root_idx)%eligible_rank_lane_sample_count, 6, 61)
      call expect_int(summary%entries(root_idx)%participating_rank_lane_sample_count, 6, 62)
      call expect_int(summary%entries(root_idx)%missing_rank_lane_sample_count, 0, 63)
      if (.not. summary%entries(root_idx)%missing_rank_lane_sample_count_known) error stop 64
      call expect_time(summary%entries(root_idx)%sum_participating_lane_inclusive_time, &
                       48.0_wp, 65)
      call expect_time(summary%entries(root_idx)%sum_participating_lane_self_time, 48.0_wp, 66)
      call expect_time(summary%entries(root_idx)%min_participating_lane_inclusive_time, &
                       3.0_wp, 67)
      call expect_time(summary%entries(root_idx)%avg_participating_lane_inclusive_time, &
                       8.0_wp, 68)
      call expect_time(summary%entries(root_idx)%max_participating_lane_inclusive_time, &
                       12.0_wp, 69)
      call expect_time(summary%entries(root_idx)%participating_lane_inclusive_imbalance, &
                       1.5_wp, 70)
      call expect_time(summary%entries(root_idx)%min_participating_lane_self_time, 3.0_wp, 71)
      call expect_time(summary%entries(root_idx)%avg_participating_lane_self_time, 8.0_wp, 72)
      call expect_time(summary%entries(root_idx)%max_participating_lane_self_time, 12.0_wp, 73)
      call expect_time(summary%entries(root_idx)%participating_lane_self_imbalance, 1.5_wp, 74)
      call expect_int64(summary%entries(root_idx)%min_participating_lane_call_count, 1_int64, 75)
      call expect_time(summary%entries(root_idx)%avg_participating_lane_call_count, 1.0_wp, 76)
      call expect_int64(summary%entries(root_idx)%max_participating_lane_call_count, 1_int64, 77)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 78)
   end subroutine check_three_rank_hybrid_rank_metrics

   subroutine check_three_rank_sparse_union_participation(rank)
      integer, intent(in) :: rank
      type(ftimer_mpi_openmp_union_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_parallel_region_t) :: region
      type(ftimer_openmp_t) :: timer
      integer :: ierr
      integer :: rank_only_id
      integer :: rank_only_idx
      integer :: serial_id
      integer :: serial_idx
      integer :: shared_id
      integer :: shared_idx
      integer :: team_size

      config%max_lanes = 4
      call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 300)

      fake_lane_time(0) = 3000.0_wp
      call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 301)

      select case (rank)
      case (0)
         call timer%register_timer('serial_sparse_3', serial_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 302)
         call timer%register_timer('shared_sparse_3', shared_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 303)
         call timer%register_timer('rank2_only_sparse_3', rank_only_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 304)
      case (1)
         call timer%register_timer('shared_sparse_3', shared_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 305)
         call timer%register_timer('serial_sparse_3', serial_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 306)
         call timer%register_timer('rank2_only_sparse_3', rank_only_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 307)
      case default
         call timer%register_timer('rank2_only_sparse_3', rank_only_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 308)
         call timer%register_timer('shared_sparse_3', shared_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 309)
         call timer%register_timer('serial_sparse_3', serial_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 310)
      end select

      if (rank /= 1) then
         fake_lane_time(0) = 3002.0_wp
         call timer%start_id(serial_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 311)
         fake_lane_time(0) = 3002.0_wp + merge(4.0_wp, 6.0_wp, rank == 0)
         call timer%stop_id(serial_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 312)
      end if

      fake_lane_time(0) = 3010.0_wp
      call timer%begin_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 313)

      team_size = merge(2, 3, rank == 0)
!$omp parallel num_threads(team_size) default(shared) private(ierr)
      fake_lane_time(1 + omp_get_thread_num()) = 0.0_wp
      call timer%start_id(shared_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 314
      fake_lane_time(1 + omp_get_thread_num()) = shared_sparse_3_duration(rank, omp_get_thread_num())
      call timer%stop_id(shared_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 315

      if (rank == 2) then
         fake_lane_time(1 + omp_get_thread_num()) = 20.0_wp
         call timer%start_id(rank_only_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 316
         fake_lane_time(1 + omp_get_thread_num()) = 20.0_wp + &
                                                    rank2_only_sparse_3_duration(omp_get_thread_num())
         call timer%stop_id(rank_only_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 317
      end if
!$omp end parallel

      fake_lane_time(0) = sparse_3_region_end_time(rank)
      call timer%end_parallel_region(region, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 318)

      fake_lane_time(0) = sparse_3_summary_end_time(rank)
      call timer%mpi_openmp_union_summary(summary, ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 319)

      call expect_int(summary%num_ranks, 3, 320)
      call expect_int(summary%num_entries, 3, 321)
      call expect_time(summary%min_rank_summary_window_time, 30.0_wp, 322)
      call expect_time(summary%avg_rank_summary_window_time, 40.0_wp, 323)
      call expect_time(summary%max_rank_summary_window_time, 50.0_wp, 324)
      call expect_time(summary%rank_summary_window_imbalance, 50.0_wp/40.0_wp, 325)
      call expect_int(summary%min_rank_summary_window_time_rank, 0, 326)
      call expect_int(summary%max_rank_summary_window_time_rank, 2, 327)
      call expect_time(summary%min_rank_timed_region_envelope_time, 10.0_wp, 328)
      call expect_time(summary%avg_rank_timed_region_envelope_time, 12.0_wp, 329)
      call expect_time(summary%max_rank_timed_region_envelope_time, 14.0_wp, 330)
      call expect_time(summary%rank_timed_region_envelope_imbalance, 14.0_wp/12.0_wp, 331)
      call expect_time(summary%min_rank_sum_lane_root_inclusive_time, 8.0_wp, 332)
      call expect_time(summary%avg_rank_sum_lane_root_inclusive_time, 65.0_wp/3.0_wp, 333)
      call expect_time(summary%max_rank_sum_lane_root_inclusive_time, 46.0_wp, 334)
      call expect_time(summary%rank_sum_lane_root_inclusive_imbalance, 46.0_wp/(65.0_wp/3.0_wp), 335)
      call expect_time(summary%min_rank_sum_lane_self_time, 8.0_wp, 336)
      call expect_time(summary%avg_rank_sum_lane_self_time, 65.0_wp/3.0_wp, 337)
      call expect_time(summary%max_rank_sum_lane_self_time, 46.0_wp, 338)
      call expect_time(summary%rank_sum_lane_self_imbalance, 46.0_wp/(65.0_wp/3.0_wp), 339)
      call expect_int(size(summary%ranks), 3, 340)
      call expect_int(summary%ranks(1)%rank, 0, 341)
      call expect_int(summary%ranks(1)%observed_participating_lane_count, 3, 342)
      call expect_time(summary%ranks(1)%summary_window_time, 30.0_wp, 343)
      call expect_time(summary%ranks(1)%sum_lane_root_inclusive_time, 8.0_wp, 344)
      call expect_int(summary%ranks(2)%rank, 1, 345)
      call expect_int(summary%ranks(2)%observed_participating_lane_count, 3, 346)
      call expect_time(summary%ranks(2)%summary_window_time, 40.0_wp, 347)
      call expect_time(summary%ranks(2)%sum_lane_root_inclusive_time, 11.0_wp, 348)
      call expect_int(summary%ranks(3)%rank, 2, 349)
      call expect_int(summary%ranks(3)%observed_participating_lane_count, 4, 350)
      call expect_time(summary%ranks(3)%summary_window_time, 50.0_wp, 351)
      call expect_time(summary%ranks(3)%sum_lane_root_inclusive_time, 46.0_wp, 352)

      serial_idx = find_union_entry(summary, 'serial_sparse_3', 0)
      shared_idx = find_union_entry(summary, 'shared_sparse_3', 0)
      rank_only_idx = find_union_entry(summary, 'rank2_only_sparse_3', 0)
      if (serial_idx <= 0) error stop 353
      if (shared_idx <= 0) error stop 354
      if (rank_only_idx <= 0) error stop 355
      call expect_union_entry(summary, serial_idx, execution_domain='serial_lane', depth=0, &
                              rank_count=2, missing_ranks=1, eligible_samples=2, &
                              participating_samples=2, missing_samples=0, sum_inclusive=10.0_wp, &
                              sum_self=10.0_wp, min_inclusive=4.0_wp, avg_inclusive=5.0_wp, &
                              max_inclusive=6.0_wp, inclusive_imbalance=6.0_wp/5.0_wp, &
                              min_self=4.0_wp, avg_self=5.0_wp, max_self=6.0_wp, &
                              self_imbalance=6.0_wp/5.0_wp, min_calls=1_int64, avg_calls=1.0_wp, &
                              max_calls=1_int64, min_pct=pct_time(6.0_wp, 50.0_wp), &
                              avg_pct=0.5_wp*(pct_time(4.0_wp, 30.0_wp) + pct_time(6.0_wp, 50.0_wp)), &
                              max_pct=pct_time(4.0_wp, 30.0_wp), &
                              pct_imbalance=pct_time(4.0_wp, 30.0_wp)/ &
                              (0.5_wp*(pct_time(4.0_wp, 30.0_wp) + &
                                       pct_time(6.0_wp, 50.0_wp))), stop_code=356)
      call expect_union_entry(summary, shared_idx, execution_domain='openmp_level1_team', depth=0, &
                              rank_count=3, missing_ranks=0, eligible_samples=8, &
                              participating_samples=8, missing_samples=0, sum_inclusive=32.0_wp, &
                              sum_self=32.0_wp, min_inclusive=2.0_wp, avg_inclusive=4.0_wp, &
                              max_inclusive=6.0_wp, inclusive_imbalance=1.5_wp, min_self=2.0_wp, &
                              avg_self=4.0_wp, max_self=6.0_wp, self_imbalance=1.5_wp, &
                              min_calls=1_int64, avg_calls=1.0_wp, max_calls=1_int64, &
                              min_pct=pct_time(2.0_wp, 30.0_wp), &
                              avg_pct=0.125_wp*(pct_time(2.0_wp, 30.0_wp) + pct_time(2.0_wp, 30.0_wp) + &
                                                pct_time(3.0_wp, 40.0_wp) + &
                                                pct_time(4.0_wp, 40.0_wp) + pct_time(4.0_wp, 40.0_wp) + &
                                                pct_time(5.0_wp, 50.0_wp) + pct_time(6.0_wp, 50.0_wp) + &
                                                pct_time(6.0_wp, 50.0_wp)), &
                              max_pct=pct_time(6.0_wp, 50.0_wp), &
                              pct_imbalance=pct_time(6.0_wp, 50.0_wp)/ &
                              (0.125_wp*(pct_time(2.0_wp, 30.0_wp) + &
                                         pct_time(2.0_wp, 30.0_wp) + &
                                         pct_time(3.0_wp, 40.0_wp) + &
                                         pct_time(4.0_wp, 40.0_wp) + &
                                         pct_time(4.0_wp, 40.0_wp) + &
                                         pct_time(5.0_wp, 50.0_wp) + &
                                         pct_time(6.0_wp, 50.0_wp) + &
                                         pct_time(6.0_wp, 50.0_wp))), stop_code=381)
      call expect_union_entry(summary, rank_only_idx, execution_domain='openmp_level1_team', depth=0, &
                              rank_count=1, missing_ranks=2, eligible_samples=3, &
                              participating_samples=3, missing_samples=0, sum_inclusive=23.0_wp, &
                              sum_self=23.0_wp, min_inclusive=7.0_wp, avg_inclusive=23.0_wp/3.0_wp, &
                              max_inclusive=8.0_wp, inclusive_imbalance=8.0_wp/(23.0_wp/3.0_wp), &
                              min_self=7.0_wp, avg_self=23.0_wp/3.0_wp, max_self=8.0_wp, &
                              self_imbalance=8.0_wp/(23.0_wp/3.0_wp), min_calls=1_int64, avg_calls=1.0_wp, &
                              max_calls=1_int64, min_pct=pct_time(7.0_wp, 50.0_wp), &
                              avg_pct=(pct_time(7.0_wp, 50.0_wp) + &
                                       pct_time(8.0_wp, 50.0_wp) + pct_time(8.0_wp, 50.0_wp))/3.0_wp, &
                              max_pct=pct_time(8.0_wp, 50.0_wp), &
                              pct_imbalance=pct_time(8.0_wp, 50.0_wp)/ &
                              ((pct_time(7.0_wp, 50.0_wp) + &
                                pct_time(8.0_wp, 50.0_wp) + &
                                pct_time(8.0_wp, 50.0_wp))/3.0_wp), stop_code=406)

      call timer%finalize(ierr=ierr)
      call expect_status(ierr, FTIMER_SUCCESS, 431)
   end subroutine check_three_rank_sparse_union_participation

   subroutine check_three_rank_explicit_subcomm(world_rank)
      integer, intent(in) :: world_rank
      type(MPI_Comm) :: subcomm
      type(ftimer_mpi_openmp_summary_t) :: summary
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer
      integer :: color
      integer :: ierr
      integer :: local_rank
      integer :: root_id
      integer :: root_idx

      color = merge(0, MPI_UNDEFINED, world_rank > 0)
      call MPI_Comm_split(MPI_COMM_WORLD, color, world_rank, subcomm, ierr)
      if (ierr /= MPI_SUCCESS) error stop 80

      if (world_rank > 0) then
         call MPI_Comm_rank(subcomm, local_rank, ierr)
         if (ierr /= MPI_SUCCESS) error stop 81
         config%max_lanes = 3
         call timer%init(config=config, comm=subcomm, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 82)

         fake_lane_time(0) = 0.0_wp
         call timer%test_set_clock(mock_openmp_clock, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 83)
         call timer%register_timer('subcomm_serial_root', root_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 84)

         fake_lane_time(0) = 1.0_wp
         call timer%start_id(root_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 85)
         fake_lane_time(0) = merge(3.0_wp, 5.0_wp, local_rank == 0)
         call timer%stop_id(root_id, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 86)
         fake_lane_time(0) = merge(5.0_wp, 9.0_wp, local_rank == 0)
         call timer%mpi_openmp_summary(summary, ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 87)

         call expect_int(summary%num_ranks, 2, 88)
         call expect_int(summary%ranks(1)%rank, 0, 89)
         call expect_int(summary%ranks(2)%rank, 1, 90)
         call expect_int(summary%min_rank_summary_window_time_rank, 0, 91)
         call expect_int(summary%max_rank_summary_window_time_rank, 1, 92)
         call expect_time(summary%min_rank_summary_window_time, 5.0_wp, 93)
         call expect_time(summary%avg_rank_summary_window_time, 7.0_wp, 94)
         call expect_time(summary%max_rank_summary_window_time, 9.0_wp, 95)
         call expect_time(summary%min_rank_sum_lane_root_inclusive_time, 2.0_wp, 96)
         call expect_time(summary%avg_rank_sum_lane_root_inclusive_time, 3.0_wp, 97)
         call expect_time(summary%max_rank_sum_lane_root_inclusive_time, 4.0_wp, 98)

         root_idx = find_entry(summary, 'subcomm_serial_root', 0)
         if (root_idx <= 0) error stop 99
         if (trim(summary%entries(root_idx)%execution_domain) /= 'serial_lane') &
            error stop 100
         call expect_int(summary%entries(root_idx)%participating_rank_count, 2, 101)
         call expect_int(summary%entries(root_idx)%eligible_rank_lane_sample_count, 2, 102)
         call expect_int(summary%entries(root_idx)%participating_rank_lane_sample_count, 2, 103)
         call expect_time(summary%entries(root_idx)%sum_participating_lane_inclusive_time, &
                          6.0_wp, 104)
         call expect_time(summary%entries(root_idx)%avg_participating_lane_inclusive_time, &
                          3.0_wp, 105)

         call timer%finalize(ierr=ierr)
         call expect_status(ierr, FTIMER_SUCCESS, 106)
         call MPI_Comm_free(subcomm, ierr)
         if (ierr /= MPI_SUCCESS) error stop 107
      end if

      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      if (ierr /= MPI_SUCCESS) error stop 108
   end subroutine check_three_rank_explicit_subcomm

   real(wp) function worker_stop_time(rank, thread_num) result(t)
      integer, intent(in) :: rank
      integer, intent(in) :: thread_num

      select case (rank)
      case (0)
         t = 3.0_wp
      case (1)
         t = merge(10.0_wp, 11.0_wp, thread_num == 0)
      case default
         t = merge(9.0_wp, 12.0_wp, thread_num == 0)
      end select
   end function worker_stop_time

   real(wp) function timed_region_end_time(rank) result(t)
      integer, intent(in) :: rank

      select case (rank)
      case (0, 1)
         t = 7.0_wp
      case default
         t = 13.0_wp
      end select
   end function timed_region_end_time

   real(wp) function summary_window_end_time(rank) result(t)
      integer, intent(in) :: rank

      select case (rank)
      case (0)
         t = 10.0_wp
      case (1)
         t = 13.0_wp
      case default
         t = 30.0_wp
      end select
   end function summary_window_end_time

   real(wp) function shared_sparse_3_duration(rank, thread_num) result(duration)
      integer, intent(in) :: rank
      integer, intent(in) :: thread_num

      select case (rank)
      case (0)
         duration = 2.0_wp
      case (1)
         duration = merge(3.0_wp, 4.0_wp, thread_num == 0)
      case default
         duration = merge(5.0_wp, 6.0_wp, thread_num == 0)
      end select
   end function shared_sparse_3_duration

   real(wp) function rank2_only_sparse_3_duration(thread_num) result(duration)
      integer, intent(in) :: thread_num

      duration = merge(7.0_wp, 8.0_wp, thread_num == 0)
   end function rank2_only_sparse_3_duration

   real(wp) function sparse_3_region_end_time(rank) result(t)
      integer, intent(in) :: rank

      select case (rank)
      case (0)
         t = 3020.0_wp
      case (1)
         t = 3022.0_wp
      case default
         t = 3024.0_wp
      end select
   end function sparse_3_region_end_time

   real(wp) function sparse_3_summary_end_time(rank) result(t)
      integer, intent(in) :: rank

      select case (rank)
      case (0)
         t = 3030.0_wp
      case (1)
         t = 3040.0_wp
      case default
         t = 3050.0_wp
      end select
   end function sparse_3_summary_end_time

   real(wp) function pct_time(duration, window) result(percent)
      real(wp), intent(in) :: duration
      real(wp), intent(in) :: window

      percent = 100.0_wp*duration/window
   end function pct_time

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

   subroutine expect_union_entry(summary, idx, execution_domain, depth, rank_count, missing_ranks, eligible_samples, &
                                 participating_samples, missing_samples, sum_inclusive, sum_self, &
                                 min_inclusive, avg_inclusive, max_inclusive, inclusive_imbalance, min_self, &
                                 avg_self, max_self, self_imbalance, min_calls, avg_calls, max_calls, &
                                 min_pct, avg_pct, max_pct, pct_imbalance, stop_code)
      type(ftimer_mpi_openmp_union_summary_t), intent(in) :: summary
      integer, intent(in) :: idx
      character(len=*), intent(in) :: execution_domain
      integer, intent(in) :: depth
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
      real(wp), intent(in) :: inclusive_imbalance
      real(wp), intent(in) :: min_self
      real(wp), intent(in) :: avg_self
      real(wp), intent(in) :: max_self
      real(wp), intent(in) :: self_imbalance
      integer(int64), intent(in) :: min_calls
      real(wp), intent(in) :: avg_calls
      integer(int64), intent(in) :: max_calls
      real(wp), intent(in) :: min_pct
      real(wp), intent(in) :: avg_pct
      real(wp), intent(in) :: max_pct
      real(wp), intent(in) :: pct_imbalance
      integer, intent(in) :: stop_code

      if (trim(summary%entries(idx)%execution_domain) /= execution_domain) error stop stop_code
      call expect_int(summary%entries(idx)%depth, depth, stop_code + 1)
      call expect_int(summary%entries(idx)%participating_rank_count, rank_count, stop_code + 2)
      call expect_int(summary%entries(idx)%missing_rank_count, missing_ranks, stop_code + 3)
      call expect_int(summary%entries(idx)%eligible_rank_lane_sample_count, eligible_samples, stop_code + 4)
      call expect_int(summary%entries(idx)%participating_rank_lane_sample_count, &
                      participating_samples, stop_code + 5)
      call expect_int(summary%entries(idx)%missing_rank_lane_sample_count, missing_samples, stop_code + 6)
      if (.not. summary%entries(idx)%missing_rank_lane_sample_count_known) error stop stop_code + 7
      call expect_time(summary%entries(idx)%sum_participating_lane_inclusive_time, &
                       sum_inclusive, stop_code + 8)
      call expect_time(summary%entries(idx)%sum_participating_lane_self_time, sum_self, stop_code + 9)
      call expect_time(summary%entries(idx)%min_participating_lane_inclusive_time, &
                       min_inclusive, stop_code + 10)
      call expect_time(summary%entries(idx)%avg_participating_lane_inclusive_time, &
                       avg_inclusive, stop_code + 11)
      call expect_time(summary%entries(idx)%max_participating_lane_inclusive_time, &
                       max_inclusive, stop_code + 12)
      call expect_time(summary%entries(idx)%participating_lane_inclusive_imbalance, &
                       inclusive_imbalance, stop_code + 13)
      call expect_time(summary%entries(idx)%min_participating_lane_self_time, min_self, stop_code + 14)
      call expect_time(summary%entries(idx)%avg_participating_lane_self_time, avg_self, stop_code + 15)
      call expect_time(summary%entries(idx)%max_participating_lane_self_time, max_self, stop_code + 16)
      call expect_time(summary%entries(idx)%participating_lane_self_imbalance, self_imbalance, stop_code + 17)
      call expect_int64(summary%entries(idx)%min_participating_lane_call_count, min_calls, stop_code + 18)
      call expect_time(summary%entries(idx)%avg_participating_lane_call_count, avg_calls, stop_code + 19)
      call expect_int64(summary%entries(idx)%max_participating_lane_call_count, max_calls, stop_code + 20)
      call expect_time(summary%entries(idx)%min_participating_lane_pct_time, min_pct, stop_code + 21)
      call expect_time(summary%entries(idx)%avg_participating_lane_pct_time, avg_pct, stop_code + 22)
      call expect_time(summary%entries(idx)%max_participating_lane_pct_time, max_pct, stop_code + 23)
      call expect_time(summary%entries(idx)%participating_lane_pct_imbalance, pct_imbalance, stop_code + 24)
   end subroutine expect_union_entry

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

end program ftimer_openmp_mpi_summary_3rank_smoke
