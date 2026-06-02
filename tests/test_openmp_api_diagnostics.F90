program ftimer_openmp_api_diagnostics
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_SUCCESS
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
   implicit none

   call omp_set_dynamic(.false.)

   call run_diagnostic_case(retained_count=1, worker_count=1, omitted_call_count=3, drain_mode=1)
   call run_diagnostic_case(retained_count=0, worker_count=1, omitted_call_count=2, drain_mode=1)
   if (available_worker_count(3) >= 3) then
      call run_diagnostic_case(retained_count=2, worker_count=3, omitted_call_count=2, drain_mode=1)
   else
      call run_diagnostic_case(retained_count=2, worker_count=1, omitted_call_count=6, drain_mode=1)
   end if
   call run_diagnostic_case(retained_count=1, worker_count=1, omitted_call_count=2, drain_mode=2)
   call run_diagnostic_case(retained_count=1, worker_count=1, omitted_call_count=2, drain_mode=3)

contains

   integer function available_worker_count(requested_worker_count) result(worker_count)
      integer, intent(in) :: requested_worker_count

      worker_count = 0
!$omp parallel num_threads(requested_worker_count + 1) default(shared) reduction(+:worker_count)
      if (omp_get_thread_num() /= 0) worker_count = worker_count + 1
!$omp end parallel
   end function available_worker_count

   subroutine run_diagnostic_case(retained_count, worker_count, omitted_call_count, drain_mode)
      integer, intent(in) :: retained_count
      integer, intent(in) :: worker_count
      integer, intent(in) :: omitted_call_count
      integer, intent(in) :: drain_mode
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

!$omp parallel num_threads(worker_count + 1) default(shared) private(i) reduction(+:worker_seen)
      if (omp_get_thread_num() /= 0) then
         worker_seen = worker_seen + 1
         do i = 1, omitted_call_count
            call timer%stop_id(timer_id)
         end do
      end if
!$omp end parallel

      if (worker_seen /= worker_count) error stop 3

      select case (drain_mode)
      case (1)
         call timer%finalize()
         call timer%finalize()
      case (2)
         call timer%reset()
         call timer%lookup_timer("diagnostic_work", timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 4
         call timer%finalize()
      case (3)
         call timer%init(config=config)
         call timer%lookup_timer("diagnostic_work", timer_id, ierr=ierr)
         if (ierr == FTIMER_SUCCESS) error stop 5
         call timer%register_timer("after_reinit", timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 6
         call timer%finalize()
      case default
         error stop 7
      end select
   end subroutine run_diagnostic_case
end program ftimer_openmp_api_diagnostics
