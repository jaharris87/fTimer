program ftimer_openmp_api_diagnostics
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_ERR_NOT_IMPLEMENTED, FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS
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
   call run_diagnostic_case(retained_count=1, worker_count=1, omitted_call_count=2, drain_mode=4)
   call run_diagnostic_case(retained_count=1, worker_count=1, omitted_call_count=2, drain_mode=5)
   call run_diagnostic_case(retained_count=1, worker_count=1, omitted_call_count=2, drain_mode=6)
   call run_reinit_config_case()
   call run_worker_lifecycle_catalog_no_ierr_case()

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
      case (4)
         call timer%finalize(ierr=ierr)
         if (ierr /= FTIMER_ERR_NOT_IMPLEMENTED) error stop 7
         call timer%finalize(ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 8
      case (5)
         call timer%reset(ierr=ierr)
         if (ierr /= FTIMER_ERR_NOT_IMPLEMENTED) error stop 9
         call timer%lookup_timer("diagnostic_work", timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 10
         call timer%finalize(ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 11
      case (6)
         call timer%init(config=config, ierr=ierr)
         if (ierr /= FTIMER_ERR_NOT_IMPLEMENTED) error stop 12
         call timer%lookup_timer("diagnostic_work", timer_id, ierr=ierr)
         if (ierr /= FTIMER_ERR_UNKNOWN) error stop 13
         call timer%register_timer("after_reinit", timer_id, ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 14
         call timer%finalize(ierr=ierr)
         if (ierr /= FTIMER_SUCCESS) error stop 15
      case default
         error stop 16
      end select
   end subroutine run_diagnostic_case

   subroutine run_reinit_config_case()
      integer :: ierr
      integer :: i
      integer :: timer_id
      integer :: worker_seen
      type(ftimer_openmp_config_t) :: initial_config
      type(ftimer_openmp_config_t) :: reinit_config
      type(ftimer_openmp_t) :: timer

      initial_config%max_lanes = 0
      initial_config%max_worker_diagnostics = 3
      reinit_config%max_lanes = 0
      reinit_config%max_worker_diagnostics = 1

      call timer%init(config=initial_config, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 17

      call timer%init(config=reinit_config, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 18

      call timer%register_timer("reinit_config_work", timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 19

      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(i) reduction(+:worker_seen)
      if (omp_get_thread_num() /= 0) then
         worker_seen = worker_seen + 1
         do i = 1, 3
            call timer%stop_id(timer_id)
         end do
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 20

      call timer%finalize()
   end subroutine run_reinit_config_case

   subroutine run_worker_lifecycle_catalog_no_ierr_case()
      integer :: ierr
      integer :: timer_id
      integer :: worker_seen
      integer :: worker_timer_id
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_t) :: timer

      config%max_lanes = 0
      config%max_worker_diagnostics = 3

      call timer%init(config=config, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 21

      call timer%register_timer("diagnostic_work", timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 22

      worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(worker_timer_id) reduction(+:worker_seen)
      if (omp_get_thread_num() /= 0) then
         worker_seen = worker_seen + 1
         call timer%reset()
         call timer%finalize()
         call timer%register_timer("worker_created", worker_timer_id)
      end if
!$omp end parallel

      if (worker_seen /= 1) error stop 23

      call timer%lookup_timer("diagnostic_work", timer_id, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 24

      call timer%lookup_timer("worker_created", worker_timer_id, ierr=ierr)
      if (ierr /= FTIMER_ERR_UNKNOWN) error stop 25

      call timer%finalize()
      call timer%finalize(ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 26
   end subroutine run_worker_lifecycle_catalog_no_ierr_case
end program ftimer_openmp_api_diagnostics
