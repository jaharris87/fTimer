program basic_usage
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_init, &
                     ftimer_print_summary, ftimer_start, ftimer_stop
   use ftimer_types, only: ftimer_summary_t, wp
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Finalize, MPI_Init
#endif
   implicit none
   integer :: i
   integer :: ierr
   real :: accumulator
   type(ftimer_summary_t) :: summary

#ifdef FTIMER_USE_MPI
   call MPI_Init(ierr)
   if (ierr /= 0) error stop 7
#endif

   call ftimer_init()
   call ftimer_start("work")

   accumulator = 0.0
   do i = 1, 200000
      accumulator = accumulator + real(i)
   end do

   call ftimer_stop("work")
   call ftimer_get_summary(summary)

   if (summary%num_entries /= 1) error stop 1
   if (.not. allocated(summary%entries)) error stop 2
   if (trim(summary%entries(1)%name) /= "work") error stop 3
   if (summary%entries(1)%call_count /= 1) error stop 4
   if (summary%entries(1)%inclusive_time < 0.0_wp) error stop 5
   if (summary%entries(1)%self_time < 0.0_wp) error stop 6

   print '(a,i0)', "Recorded timers: ", summary%num_entries
   call ftimer_print_summary()
   call ftimer_finalize()
#ifdef FTIMER_USE_MPI
   call MPI_Finalize(ierr)
   if (ierr /= 0) error stop 8
#endif
   if (accumulator < 0.0) print *, accumulator
end program basic_usage
