program ftimer_openmp_option_off_global_flags
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_init, ftimer_start, ftimer_stop
   use ftimer_types, only: FTIMER_SUCCESS, ftimer_summary_t
   implicit none

   type(ftimer_summary_t) :: summary
   integer :: ierr
   integer :: thread_num
   logical :: thread_seen(2)
   logical :: names_match

   call omp_set_dynamic(.false.)
   thread_seen = .false.

   call ftimer_init(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 1

!$omp parallel num_threads(2) default(shared) private(thread_num)
   thread_num = omp_get_thread_num()
   if (thread_num + 1 <= size(thread_seen)) thread_seen(thread_num + 1) = .true.

   if (thread_num /= 0) then
      call ftimer_start("worker_recorded", ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 2

      call ftimer_stop("worker_recorded", ierr=ierr)
      if (ierr /= FTIMER_SUCCESS) error stop 3
   end if
!$omp end parallel

   if (.not. thread_seen(1)) error stop 4
   if (.not. thread_seen(2)) error stop 5

   call ftimer_get_summary(summary, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 6
   if (summary%num_entries /= 1) error stop 7

   names_match = trim(summary%entries(1)%name) == 'worker_recorded'
   if (.not. names_match) error stop 8
   if (summary%entries(1)%call_count /= 1) error stop 9

   call ftimer_finalize(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 10
end program ftimer_openmp_option_off_global_flags
