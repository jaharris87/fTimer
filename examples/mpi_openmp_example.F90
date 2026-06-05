program mpi_openmp_example
   use ftimer_openmp, only: ftimer_mpi_openmp_summary_t, ftimer_mpi_openmp_union_summary_t, &
                            ftimer_openmp_config_t, &
                            ftimer_openmp_parallel_region_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_SUCCESS, wp
   use mpi_f08, only: MPI_COMM_WORLD, MPI_Comm_rank, MPI_Comm_size, MPI_Finalize, &
                      MPI_Init, MPI_SUCCESS
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
   implicit none

   integer :: all_lanes_id
   integer :: all_lanes_idx
   integer :: ierr
   integer :: i
   integer :: nprocs
   integer :: rank
   integer :: sparse_id
   integer :: sparse_idx
   integer :: worker_bad
   integer :: worker_seen
   real(wp) :: accumulator
   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_parallel_region_t) :: region
   type(ftimer_mpi_openmp_summary_t) :: strict_summary
   type(ftimer_mpi_openmp_union_summary_t) :: union_summary
   type(ftimer_openmp_t) :: timer

   call MPI_Init(ierr)
   if (ierr /= MPI_SUCCESS) error stop "MPI_Init failed"
   call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
   if (ierr /= MPI_SUCCESS) error stop "MPI_Comm_rank failed"
   call MPI_Comm_size(MPI_COMM_WORLD, nprocs, ierr)
   if (ierr /= MPI_SUCCESS) error stop "MPI_Comm_size failed"

   call omp_set_dynamic(.false.)

   config%max_lanes = 3
   config%max_worker_diagnostics = 4

   call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "ftimer_openmp init failed"

   call timer%register_timer("hybrid_all_lanes", all_lanes_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "register hybrid_all_lanes failed"

   call timer%begin_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "begin strict hybrid region failed"

   accumulator = 0.0_wp
   worker_bad = 0
   worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr, i) &
!$omp& reduction(+:accumulator, worker_bad, worker_seen)
   worker_seen = worker_seen + 1

   call timer%start_id(all_lanes_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1

   do i = 1, (rank + omp_get_thread_num() + 1)*40000
      accumulator = accumulator + real(i, wp)*0.25_wp
   end do

   call timer%stop_id(all_lanes_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
!$omp end parallel

   if (worker_seen /= 2) error stop "strict hybrid example expected two threads"
   if (worker_bad /= 0) error stop "strict hybrid worker timing failed"

   call timer%end_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "end strict hybrid region failed"

   call timer%mpi_openmp_summary(strict_summary, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "strict MPI+OpenMP summary failed"

   all_lanes_idx = find_strict_entry(strict_summary, "hybrid_all_lanes")
   if (all_lanes_idx <= 0) error stop "strict hybrid summary missing hybrid_all_lanes"
   if (strict_summary%num_ranks /= nprocs) error stop "strict hybrid rank count mismatch"
   if (strict_summary%entries(all_lanes_idx)%participating_rank_count /= nprocs) &
      error stop "strict hybrid participating rank count mismatch"
   if (strict_summary%entries(all_lanes_idx)%participating_rank_lane_sample_count /= nprocs*2) &
      error stop "strict hybrid participating rank/lane count mismatch"

   if (rank == 0) then
      print '(a)', "Strict MPI+OpenMP worker timing with ftimer_openmp_t"
      print '(a,i0)', "MPI ranks: ", nprocs
      print '(a,i0)', "Participating rank/lane samples: ", &
         strict_summary%entries(all_lanes_idx)%participating_rank_lane_sample_count
   end if
   call timer%print_mpi_openmp_summary(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "print strict MPI+OpenMP summary failed"
   call timer%write_mpi_openmp_summary_csv("mpi_openmp_strict_summary.csv", ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "write strict MPI+OpenMP CSV failed"

   call timer%register_timer("rank0_lane0_only", sparse_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "register rank0_lane0_only failed"

   call timer%begin_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "begin sparse hybrid region failed"

   worker_bad = 0
!$omp parallel num_threads(2) default(shared) private(ierr, i) reduction(+:accumulator, worker_bad)
   if (rank == 0 .and. omp_get_thread_num() == 0) then
      call timer%start_id(sparse_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1

      do i = 1, 30000
         accumulator = accumulator + real(i, wp)*0.125_wp
      end do

      call timer%stop_id(sparse_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
   end if
!$omp end parallel

   if (worker_bad /= 0) error stop "sparse hybrid worker timing failed"

   call timer%end_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "end sparse hybrid region failed"

   call timer%mpi_openmp_union_summary(union_summary, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "sparse MPI+OpenMP union summary failed"

   sparse_idx = find_union_entry(union_summary, "rank0_lane0_only")
   if (sparse_idx <= 0) error stop "sparse hybrid summary missing rank0_lane0_only"
   if (union_summary%entries(sparse_idx)%participating_rank_count /= 1) &
      error stop "sparse hybrid participating rank count mismatch"
   if (union_summary%entries(sparse_idx)%participating_rank_lane_sample_count /= 1) &
      error stop "sparse hybrid participating rank/lane count mismatch"

   if (rank == 0) then
      print '(a)', "Sparse MPI+OpenMP union summary for rank/lane-conditional timing"
      print '(a,i0)', "Sparse participating ranks: ", &
         union_summary%entries(sparse_idx)%participating_rank_count
   end if
   call timer%print_mpi_openmp_union_summary(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "print sparse MPI+OpenMP union summary failed"
   call timer%write_mpi_openmp_union_summary_csv("mpi_openmp_union_summary.csv", ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "write sparse MPI+OpenMP union CSV failed"

   call timer%finalize(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "ftimer_openmp finalize failed"
   call MPI_Finalize(ierr)
   if (ierr /= MPI_SUCCESS) error stop "MPI_Finalize failed"

   if (accumulator < 0.0_wp) print *, accumulator

contains

   integer function find_strict_entry(summary, name) result(entry_idx)
      type(ftimer_mpi_openmp_summary_t), intent(in) :: summary
      character(len=*), intent(in) :: name
      integer :: i

      entry_idx = 0
      do i = 1, summary%num_entries
         if (trim(summary%entries(i)%name) == name) then
            entry_idx = i
            return
         end if
      end do
   end function find_strict_entry

   integer function find_union_entry(summary, name) result(entry_idx)
      type(ftimer_mpi_openmp_union_summary_t), intent(in) :: summary
      character(len=*), intent(in) :: name
      integer :: i

      entry_idx = 0
      do i = 1, summary%num_entries
         if (trim(summary%entries(i)%name) == name) then
            entry_idx = i
            return
         end if
      end do
   end function find_union_entry

end program mpi_openmp_example
