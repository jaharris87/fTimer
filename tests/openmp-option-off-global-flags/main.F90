program ftimer_openmp_option_off_global_flags
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_guard_t, ftimer_init, &
                     ftimer_reset, ftimer_scope, ftimer_start, ftimer_stop
   use ftimer_core, only: ftimer_t
   use ftimer_types, only: FTIMER_ERR_NOT_INIT, FTIMER_SUCCESS, ftimer_summary_t
   implicit none

   integer, parameter :: IERR_SENTINEL = -1000

   call omp_set_dynamic(.false.)

   call verify_procedural_worker_paths()
   call verify_oop_worker_paths()

contains

   subroutine verify_procedural_worker_paths()
      type(ftimer_summary_t) :: summary
      integer :: ierr
      integer :: local_ierr
      integer :: thread_num
      integer :: worker_reset_ierr
      integer :: worker_scope_ierr
      integer :: worker_start_ierr
      integer :: worker_stop_ierr
      logical :: thread_seen(2)

      thread_seen = .false.
      worker_reset_ierr = IERR_SENTINEL
      worker_scope_ierr = IERR_SENTINEL
      worker_start_ierr = IERR_SENTINEL
      worker_stop_ierr = IERR_SENTINEL

      call ftimer_init(ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 1

!$omp parallel num_threads(2) default(shared) private(local_ierr, thread_num)
      thread_num = omp_get_thread_num()
      if (thread_num + 1 <= size(thread_seen)) thread_seen(thread_num + 1) = .true.

      if (thread_num /= 0) then
         local_ierr = IERR_SENTINEL
         call ftimer_start("worker_recorded", ierr=local_ierr)
         worker_start_ierr = local_ierr

         local_ierr = IERR_SENTINEL
         call ftimer_stop("worker_recorded", ierr=local_ierr)
         worker_stop_ierr = local_ierr

         worker_scope: block
            type(ftimer_guard_t) :: guard

            local_ierr = IERR_SENTINEL
            call ftimer_scope(guard, "worker_scope", ierr=local_ierr)
            worker_scope_ierr = local_ierr
         end block worker_scope
      end if
!$omp end parallel

      if (.not. thread_seen(1)) error stop 2
      if (.not. thread_seen(2)) error stop 3
      if (worker_start_ierr /= FTIMER_SUCCESS) error stop 4
      if (worker_stop_ierr /= FTIMER_SUCCESS) error stop 5
      if (worker_scope_ierr /= FTIMER_SUCCESS) error stop 6

      call ftimer_get_summary(summary, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 7
      if (summary%has_active_timers) error stop 8
      if (summary%num_entries /= 2) error stop 9
      if (summary_call_count(summary, "worker_recorded") /= 1) error stop 10
      if (summary_call_count(summary, "worker_scope") /= 1) error stop 11

      thread_seen = .false.
!$omp parallel num_threads(2) default(shared) private(local_ierr, thread_num)
      thread_num = omp_get_thread_num()
      if (thread_num + 1 <= size(thread_seen)) thread_seen(thread_num + 1) = .true.

      if (thread_num /= 0) then
         local_ierr = IERR_SENTINEL
         call ftimer_reset(ierr=local_ierr)
         worker_reset_ierr = local_ierr
      end if
!$omp end parallel

      if (.not. thread_seen(1)) error stop 12
      if (.not. thread_seen(2)) error stop 13
      if (worker_reset_ierr /= FTIMER_SUCCESS) error stop 14

      call ftimer_get_summary(summary, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 15
      if (summary%has_active_timers) error stop 16
      if (summary%num_entries /= 0) error stop 17

      call ftimer_finalize(ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 18
   end subroutine verify_procedural_worker_paths

   subroutine verify_oop_worker_paths()
      type(ftimer_t) :: timer
      type(ftimer_summary_t) :: summary
      integer :: ierr
      integer :: local_id
      integer :: local_ierr
      integer :: thread_num
      integer :: worker_finalize_ierr
      integer :: worker_id
      integer :: worker_lookup_ierr
      integer :: worker_reset_ierr
      integer :: worker_start_id_ierr
      integer :: worker_stop_id_ierr
      logical :: thread_seen(2)

      thread_seen = .false.
      worker_finalize_ierr = IERR_SENTINEL
      worker_id = 0
      worker_lookup_ierr = IERR_SENTINEL
      worker_reset_ierr = IERR_SENTINEL
      worker_start_id_ierr = IERR_SENTINEL
      worker_stop_id_ierr = IERR_SENTINEL

      call timer%init(ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 19

!$omp parallel num_threads(2) default(shared) private(local_id, local_ierr, thread_num)
      thread_num = omp_get_thread_num()
      if (thread_num + 1 <= size(thread_seen)) thread_seen(thread_num + 1) = .true.

      if (thread_num /= 0) then
         local_ierr = IERR_SENTINEL
         local_id = timer%lookup("worker_id", ierr=local_ierr)
         worker_id = local_id
         worker_lookup_ierr = local_ierr

         local_ierr = IERR_SENTINEL
         call timer%start_id(local_id, ierr=local_ierr)
         worker_start_id_ierr = local_ierr

         local_ierr = IERR_SENTINEL
         call timer%stop_id(local_id, ierr=local_ierr)
         worker_stop_id_ierr = local_ierr
      end if
!$omp end parallel

      if (.not. thread_seen(1)) error stop 20
      if (.not. thread_seen(2)) error stop 21
      if (worker_lookup_ierr /= FTIMER_SUCCESS) error stop 22
      if (worker_id <= 0) error stop 23
      if (worker_start_id_ierr /= FTIMER_SUCCESS) error stop 24
      if (worker_stop_id_ierr /= FTIMER_SUCCESS) error stop 25

      call timer%get_summary(summary, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 26
      if (summary%has_active_timers) error stop 27
      if (summary%num_entries /= 1) error stop 28
      if (summary_call_count(summary, "worker_id") /= 1) error stop 29

      thread_seen = .false.
!$omp parallel num_threads(2) default(shared) private(local_ierr, thread_num)
      thread_num = omp_get_thread_num()
      if (thread_num + 1 <= size(thread_seen)) thread_seen(thread_num + 1) = .true.

      if (thread_num /= 0) then
         local_ierr = IERR_SENTINEL
         call timer%reset(ierr=local_ierr)
         worker_reset_ierr = local_ierr
      end if
!$omp end parallel

      if (.not. thread_seen(1)) error stop 30
      if (.not. thread_seen(2)) error stop 31
      if (worker_reset_ierr /= FTIMER_SUCCESS) error stop 32

      call timer%get_summary(summary, ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 33
      if (summary%has_active_timers) error stop 34
      if (summary%num_entries /= 0) error stop 35

      thread_seen = .false.
!$omp parallel num_threads(2) default(shared) private(local_ierr, thread_num)
      thread_num = omp_get_thread_num()
      if (thread_num + 1 <= size(thread_seen)) thread_seen(thread_num + 1) = .true.

      if (thread_num /= 0) then
         local_ierr = IERR_SENTINEL
         call timer%finalize(ierr=local_ierr)
         worker_finalize_ierr = local_ierr
      end if
!$omp end parallel

      if (.not. thread_seen(1)) error stop 36
      if (.not. thread_seen(2)) error stop 37
      if (worker_finalize_ierr /= FTIMER_SUCCESS) error stop 38

      call timer%start("after_worker_finalize", ierr=ierr)
      if (ierr /= FTIMER_ERR_NOT_INIT) error stop 39
   end subroutine verify_oop_worker_paths

   integer function summary_call_count(summary, name) result(call_count)
      type(ftimer_summary_t), intent(in) :: summary
      character(len=*), intent(in) :: name
      integer :: i

      call_count = -1
      do i = 1, summary%num_entries
         if (trim(summary%entries(i)%name) == name) then
            call_count = summary%entries(i)%call_count
            return
         end if
      end do
   end function summary_call_count
end program ftimer_openmp_option_off_global_flags
