module ftimer_clock
   use, intrinsic :: iso_fortran_env, only: int64
   use ftimer_types, only: wp
   implicit none
   private

   public :: ftimer_default_clock
   public :: ftimer_mpi_clock
   public :: ftimer_date_string

contains

   function ftimer_default_clock() result(t)
      real(wp) :: t
      integer(int64) :: count
      integer(int64) :: rate

      call system_clock(count, rate)
      if (rate > 0_int64) then
         t = real(count, wp)/real(rate, wp)
      else
         t = 0.0_wp
      end if
   end function ftimer_default_clock

   function ftimer_mpi_clock() result(t)
      real(wp) :: t
#ifdef FTIMER_USE_MPI
      double precision :: MPI_Wtime
      external :: MPI_Wtime
#endif

#ifdef FTIMER_USE_MPI
      t = real(MPI_Wtime(), wp)
#else
      t = ftimer_default_clock()
#endif
   end function ftimer_mpi_clock

   function ftimer_date_string() result(stamp)
      character(len=40) :: stamp
      character(len=5) :: zone
      integer :: values(8)

      call date_and_time(values=values, zone=zone)
      write (stamp, '(i4.4,"-",i2.2,"-",i2.2," ",i2.2,":",i2.2,":",i2.2," ",a)') &
         values(1), values(2), values(3), values(5), values(6), values(7), zone
   end function ftimer_date_string

end module ftimer_clock
