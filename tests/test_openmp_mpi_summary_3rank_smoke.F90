program ftimer_openmp_mpi_summary_3rank_smoke
   use, intrinsic :: iso_fortran_env, only: int64
   use ftimer_openmp, only: ftimer_mpi_openmp_summary_t, ftimer_openmp_config_t, &
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
