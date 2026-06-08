program nested_timers
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_print_summary, &
                     ftimer_start, ftimer_stop
   use ftimer_types, only: ftimer_metadata_t
   implicit none
   integer :: i
   integer :: j
   real :: accumulator
   type(ftimer_metadata_t) :: metadata(2)

   metadata(1)%key = "case"
   metadata(1)%value = "nested_timers"
   metadata(2)%key = "steps"
   metadata(2)%value = "3"

   ! Metadata is optional, but useful for tagging solver cases or timestep
   ! batches in saved reports.
   call ftimer_init()

   ! The parent timer remains open while child timers run, so the summary shows
   ! both the total advance time and the sweep/io split underneath it.
   call ftimer_start("advance")

   accumulator = 0.0
   do i = 1, 3
      ! Reusing the same child names across iterations accumulates call counts
      ! and times under this parent context.
      call ftimer_start("sweep")
      do j = 1, 75000
         accumulator = accumulator + real(i + j)
      end do
      call ftimer_stop("sweep")

      call ftimer_start("io")
      do j = 1, 20000
         accumulator = accumulator - real(j)
      end do
      call ftimer_stop("io")
   end do

   call ftimer_stop("advance")
   call ftimer_print_summary(metadata=metadata)
   call ftimer_finalize()
   if (accumulator < 0.0) print *, accumulator
end program nested_timers
