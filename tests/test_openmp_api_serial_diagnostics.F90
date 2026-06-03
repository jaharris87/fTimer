program ftimer_openmp_api_serial_diagnostics
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_SUCCESS
   implicit none

   integer :: ierr
   integer :: timer_id
   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_t) :: timer

   call timer%register_timer("before_init", timer_id)

   config%mode = -1
   call timer%init(config=config)

   config = ftimer_openmp_config_t()
   call timer%init(config=config, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 1

   call timer%lookup_timer("missing", timer_id)

   call timer%register_timer("work", timer_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 2

   call timer%start_id(timer_id)

   call timer%finalize(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 3
end program ftimer_openmp_api_serial_diagnostics
