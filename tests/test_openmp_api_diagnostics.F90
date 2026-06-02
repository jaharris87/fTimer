program ftimer_openmp_api_diagnostics
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_SUCCESS
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
   implicit none

   call omp_set_dynamic(.false.)

   call run_diagnostic_case(retained_count=1, omitted_call_count=3)
   call run_diagnostic_case(retained_count=0, omitted_call_count=2)

contains

   subroutine run_diagnostic_case(retained_count, omitted_call_count)
      integer, intent(in) :: retained_count
      integer, intent(in) :: omitted_call_count
      integer :: ierr
      integer :: i
      integer :: timer_id
      integer :: worker_seen
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer

      config%max_lanes = 0
      config%max_worker_diagnostics = retained_count

      call timer%init(config=config, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 1

      call timer%register_timer("diagnostic_work", timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 2

      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(i) reduction(+:worker_seen)
      if (omp_get_thread_num() /= 0) then
         worker_seen = worker_seen + 1
         do i = 1, omitted_call_count
            call timer%stop_id(timer_id)
         end do
      end if
!$omp end parallel

      if (worker_seen <= 0) error stop 3

      call timer%finalize()
      call timer%finalize()
   end subroutine run_diagnostic_case
end program ftimer_openmp_api_diagnostics
