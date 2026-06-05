program ftimer_installed_openmp_api_mpi_openmp_consumer
   use ftimer_openmp, only: ftimer_mpi_openmp_summary_t, ftimer_openmp_config_t, &
                            ftimer_openmp_parallel_region_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_SUCCESS
   use mpi_f08, only: MPI_COMM_WORLD, MPI_Finalize, MPI_Init, MPI_Comm_rank, MPI_SUCCESS
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
   implicit none

   integer :: ierr
   integer :: hybrid_id
   integer :: rank
   integer :: timer_id
   integer :: worker_bad
   integer :: worker_seen
   character(len=64) :: timer_name
   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_parallel_region_t) :: region
   type(ftimer_mpi_openmp_summary_t) :: summary
   type(ftimer_openmp_t) :: timer

   call MPI_Init(ierr)
   if (ierr /= MPI_SUCCESS) error stop 1

   call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
   if (ierr /= MPI_SUCCESS) error stop 2

   call omp_set_dynamic(.false.)

   config%max_lanes = 3
   config%max_worker_diagnostics = rank + 1

   call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 3

   call timer%register_timer("consumer_hybrid_api", hybrid_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 4

   call timer%begin_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 5
!$omp parallel num_threads(2) default(shared) private(ierr)
   call timer%start_id(hybrid_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 6
   call timer%stop_id(hybrid_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 7
!$omp end parallel
   call timer%end_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 8

   call timer%mpi_openmp_summary(summary, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 9
   if (summary%num_ranks /= 2) error stop 10
   if (summary%num_entries /= 1) error stop 11
   if (trim(summary%entries(1)%name) /= "consumer_hybrid_api") error stop 12
   if (trim(summary%entries(1)%execution_domain) /= "openmp_level1_team") error stop 13
   if (summary%entries(1)%participating_rank_count /= 2) error stop 14
   if (summary%entries(1)%eligible_rank_lane_sample_count /= 4) error stop 15
   if (summary%entries(1)%participating_rank_lane_sample_count /= 4) error stop 16

   write (timer_name, '("consumer_openmp_api_mpi_openmp_rank_",i0)') rank
   call timer%register_timer(trim(timer_name), timer_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 17

   call timer%begin_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 18

   worker_bad = 0
   worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr) reduction(+:worker_bad, worker_seen)
   if (omp_get_thread_num() /= 0) then
      worker_seen = worker_seen + 1

      call timer%start_id(timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1

      call timer%stop_id(timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1

      call timer%stop_id(timer_id)
      if (rank == 1) call timer%stop_id(timer_id)
   end if
!$omp end parallel

   if (worker_seen <= 0) error stop 5
   if (worker_bad /= 0) error stop 6

   call timer%end_parallel_region(region)

   call timer%finalize()

   call MPI_Finalize(ierr)
   if (ierr /= MPI_SUCCESS) error stop 7
end program ftimer_installed_openmp_api_mpi_openmp_consumer
