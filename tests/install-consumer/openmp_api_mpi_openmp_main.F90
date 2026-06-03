program ftimer_installed_openmp_api_mpi_openmp_consumer
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_parallel_region_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_SUCCESS
   use mpi_f08, only: MPI_COMM_WORLD, MPI_Finalize, MPI_Init, MPI_Comm_rank, MPI_SUCCESS
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
   implicit none

   integer :: ierr
   integer :: rank
   integer :: timer_id
   integer :: worker_bad
   integer :: worker_seen
   character(len=64) :: timer_name
   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_parallel_region_t) :: region
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

   write (timer_name, '("consumer_openmp_api_mpi_openmp_rank_",i0)') rank
   call timer%register_timer(trim(timer_name), timer_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 4

   call timer%begin_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 8

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

   call timer%end_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 9

   call timer%finalize()

   call MPI_Finalize(ierr)
   if (ierr /= MPI_SUCCESS) error stop 7
end program ftimer_installed_openmp_api_mpi_openmp_consumer
