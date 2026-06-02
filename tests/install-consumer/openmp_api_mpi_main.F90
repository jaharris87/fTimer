program ftimer_installed_openmp_api_mpi_consumer
   use ftimer_openmp, only: FTIMER_OPENMP_MODE_THREAD_LANES, ftimer_openmp_config_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_NOT_IMPLEMENTED, FTIMER_SUCCESS
   use mpi_f08, only: MPI_COMM_WORLD, MPI_Finalize, MPI_Init, MPI_SUCCESS
   implicit none

   integer :: ierr
   integer :: timer_id
   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_t) :: timer

   call MPI_Init(ierr)
   if (ierr /= MPI_SUCCESS) error stop 1

   config%mode = FTIMER_OPENMP_MODE_THREAD_LANES
   config%max_lanes = 2

   call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 2

   call timer%register_timer("consumer_openmp_api_mpi_work", timer_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 3

   call timer%start_id(timer_id, ierr=ierr)
   if (ierr /= FTIMER_ERR_NOT_IMPLEMENTED) error stop 4

   call timer%finalize(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 5

   call MPI_Finalize(ierr)
   if (ierr /= MPI_SUCCESS) error stop 6
end program ftimer_installed_openmp_api_mpi_consumer
