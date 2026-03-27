module ftimer_clock
   use, intrinsic :: iso_fortran_env, only: int64
   use ftimer_types, only: wp
   implicit none
   private

   public :: ftimer_default_clock
   public :: ftimer_mpi_clock
   public :: ftimer_date_string

   character(len=40), save :: cached_date_stamp = ''
   integer(int64), save :: cached_date_rate = 0_int64
   integer(int64), save :: cached_next_refresh_count = 0_int64
   logical, save :: has_cached_date_stamp = .false.

contains

   function ftimer_default_clock() result(t)
      real(wp) :: t
      integer(int64) :: count
      integer(int64) :: rate

      call system_clock(count, rate)
      if (rate > 0_int64) then
         t = real(count, wp)/real(rate, wp)
      else
         error stop "ftimer_default_clock: system_clock rate unavailable"
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
      t = 0.0_wp
      error stop "ftimer_mpi_clock: FTIMER_USE_MPI is not enabled"
#endif
   end function ftimer_mpi_clock

   function ftimer_date_string() result(stamp)
      character(len=40) :: stamp
      character(len=5) :: zone
      integer(int64) :: count
      integer(int64) :: count_max
      integer(int64) :: rate
      integer :: values(8)

      call system_clock(count=count, count_rate=rate, count_max=count_max)
      if (has_cached_date_stamp .and. clock_cache_supported(rate, count_max) .and. (cached_date_rate == rate)) then
         if (count < cached_next_refresh_count) then
            stamp = cached_date_stamp
            return
         end if
      end if

      call date_and_time(values=values, zone=zone)
      write (stamp, '(i4.4,"-",i2.2,"-",i2.2," ",i2.2,":",i2.2,":",i2.2," ",a)') &
         values(1), values(2), values(3), values(5), values(6), values(7), zone

      if (clock_cache_supported(rate, count_max)) then
         call system_clock(count=count)
         cached_date_stamp = stamp
         cached_date_rate = rate
         cached_next_refresh_count = count + milliseconds_to_clock_counts(1000 - values(8), rate)
         has_cached_date_stamp = .true.
      else
         cached_date_stamp = ''
         cached_date_rate = 0_int64
         cached_next_refresh_count = 0_int64
         has_cached_date_stamp = .false.
      end if
   end function ftimer_date_string

   integer(int64) function milliseconds_to_clock_counts(milliseconds, rate) result(delta)
      integer, intent(in) :: milliseconds
      integer(int64), intent(in) :: rate
      integer(int64) :: millis64

      millis64 = int(max(milliseconds, 1), int64)
      delta = (millis64*rate + 999_int64)/1000_int64
      if (delta <= 0_int64) delta = 1_int64
   end function milliseconds_to_clock_counts

   logical function clock_cache_supported(rate, count_max) result(supported)
      integer(int64), intent(in) :: rate
      integer(int64), intent(in) :: count_max

      supported = (rate > 0_int64) .and. (count_max == huge(count_max))
   end function clock_cache_supported

end module ftimer_clock
