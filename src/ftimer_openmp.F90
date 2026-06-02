module ftimer_openmp
   use, intrinsic :: iso_fortran_env, only: error_unit
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_INVALID_NAME, FTIMER_ERR_NOT_IMPLEMENTED, &
                           FTIMER_ERR_NOT_INIT, FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Comm, MPI_COMM_WORLD
#endif
#ifdef FTIMER_USE_OPENMP
   use omp_lib, only: omp_get_max_threads, omp_in_parallel
#endif
   implicit none
   private

   public :: FTIMER_OPENMP_MODE_THREAD_LANES
   public :: ftimer_openmp_config_t
   public :: ftimer_openmp_parallel_region_t
   public :: ftimer_openmp_t

   integer, parameter :: FTIMER_OPENMP_MODE_THREAD_LANES = 1
   integer, parameter :: FTIMER_OPENMP_CATALOG_INITIAL_CAPACITY = 16
   integer, parameter :: FTIMER_OPENMP_DEFAULT_WORKER_DIAGNOSTICS = 32

   type :: ftimer_openmp_config_t
      integer :: mode = FTIMER_OPENMP_MODE_THREAD_LANES
      integer :: max_lanes = 0
      integer :: max_worker_diagnostics = FTIMER_OPENMP_DEFAULT_WORKER_DIAGNOSTICS
   end type ftimer_openmp_config_t

   type :: ftimer_openmp_parallel_region_t
      private
      integer :: epoch = 0
      logical :: active = .false.
   end type ftimer_openmp_parallel_region_t

   type :: ftimer_openmp_catalog_entry_t
      character(len=:), allocatable :: name
      integer :: id = 0
   end type ftimer_openmp_catalog_entry_t

   type :: ftimer_openmp_init_keyword_guard_t
   end type ftimer_openmp_init_keyword_guard_t

   type :: ftimer_openmp_t
      private
      logical :: initialized = .false.
      type(ftimer_openmp_config_t) :: config
      type(ftimer_openmp_catalog_entry_t), allocatable :: catalog(:)
      integer :: num_timers = 0
      integer :: next_timer_id = 1
      logical :: region_open = .false.
      integer :: current_epoch = 0
      integer :: next_epoch = 1
      integer :: queued_worker_diagnostics = 0
      integer :: worker_diagnostic_overflow = 0
      integer :: first_worker_status = FTIMER_SUCCESS
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: mpi_comm
      logical :: mpi_comm_was_present = .false.
#endif
   contains
      procedure, private :: init_without_comm
#ifdef FTIMER_USE_MPI
      procedure, private :: init_with_mpi_comm
      generic, public :: init => init_without_comm, init_with_mpi_comm
#else
      procedure, public :: init => init_without_comm
#endif
      procedure :: finalize
      procedure :: reset
      procedure :: register_timer
      procedure :: lookup_timer
      procedure :: begin_parallel_region
      procedure :: end_parallel_region
      procedure :: start_id
      procedure :: stop_id
   end type ftimer_openmp_t

contains

   subroutine init_without_comm(self, keyword_guard, config, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_init_keyword_guard_t), intent(in), optional :: keyword_guard
      type(ftimer_openmp_config_t), intent(in) :: config
      integer, intent(out), optional :: ierr

      if (present(keyword_guard)) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, &
                                  "ftimer_openmp init received an invalid positional guard argument")
         return
      end if

      call init_impl(self, config, ierr=ierr)
   end subroutine init_without_comm

#ifdef FTIMER_USE_MPI
   subroutine init_with_mpi_comm(self, keyword_guard, config, comm, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_init_keyword_guard_t), intent(in), optional :: keyword_guard
      type(ftimer_openmp_config_t), intent(in) :: config
      type(MPI_Comm), intent(in) :: comm
      integer, intent(out), optional :: ierr

      if (present(keyword_guard)) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, &
                                  "ftimer_openmp init received an invalid positional guard argument")
         return
      end if

      call init_impl(self, config, comm=comm, ierr=ierr)
   end subroutine init_with_mpi_comm
#endif

   subroutine init_impl(self, config, ierr, comm)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_config_t), intent(in) :: config
      integer, intent(out), optional :: ierr
#ifdef FTIMER_USE_MPI
      type(MPI_Comm), intent(in), optional :: comm
#else
      integer, intent(in), optional :: comm
#endif
      type(ftimer_openmp_config_t) :: effective_config

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp init called inside an OpenMP parallel region")
         return
      end if

      if (self%initialized .and. self%region_open) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp init with an open timed region; state unchanged")
         return
      end if

      effective_config = config
      if (.not. normalize_config(effective_config)) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp init with invalid configuration")
         return
      end if

      if (.not. present(ierr)) call emit_worker_diagnostics(self)
      call clear_state(self)
      self%initialized = .true.
      self%config = effective_config
#ifdef FTIMER_USE_MPI
      self%mpi_comm = MPI_COMM_WORLD
      self%mpi_comm_was_present = .false.
      if (present(comm)) then
         self%mpi_comm = comm
         self%mpi_comm_was_present = .true.
      end if
#endif

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine init_impl

   subroutine finalize(self, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp finalize called inside an OpenMP parallel region")
         return
      end if

      if (self%region_open) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp finalize with an open timed region; state unchanged")
         return
      end if

      if (.not. present(ierr)) call emit_worker_diagnostics(self)
      call clear_state(self)
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine finalize

   subroutine reset(self, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr
      type(ftimer_openmp_config_t) :: saved_config
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: saved_mpi_comm
      logical :: saved_mpi_comm_was_present
#endif

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp reset called inside an OpenMP parallel region")
         return
      end if

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp reset before init")
         return
      end if

      if (self%region_open) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp reset with an open timed region; state unchanged")
         return
      end if

      saved_config = self%config
#ifdef FTIMER_USE_MPI
      saved_mpi_comm = self%mpi_comm
      saved_mpi_comm_was_present = self%mpi_comm_was_present
#endif
      if (.not. present(ierr)) call emit_worker_diagnostics(self)
      self%initialized = .true.
      self%config = saved_config
      self%region_open = .false.
      self%current_epoch = 0
      self%next_epoch = 1
      call clear_worker_diagnostics(self)
#ifdef FTIMER_USE_MPI
      self%mpi_comm = saved_mpi_comm
      self%mpi_comm_was_present = saved_mpi_comm_was_present
#endif
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine reset

   subroutine register_timer(self, name, id, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out) :: id
      integer, intent(out), optional :: ierr
      integer :: existing_idx
      integer :: trimmed_len
      integer :: status
      character(len=:), allocatable :: message

      id = 0

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp register_timer called inside an OpenMP parallel region")
         return
      end if

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp register_timer before init")
         return
      end if

      if (self%region_open) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp register_timer with an open timed region")
         return
      end if

      call normalize_name(name, trimmed_len, status, message)
      if (status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, status, message)
         return
      end if

      existing_idx = find_timer_index(self, name(1:trimmed_len))
      if (existing_idx > 0) then
         id = self%catalog(existing_idx)%id
         if (present(ierr)) ierr = FTIMER_SUCCESS
         return
      end if

      id = allocate_timer_id(self)
      if (id <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp timer id space exhausted")
         return
      end if

      call ensure_catalog_capacity(self, self%num_timers + 1)
      self%num_timers = self%num_timers + 1
      self%catalog(self%num_timers)%name = name(1:trimmed_len)
      self%catalog(self%num_timers)%id = id

      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine register_timer

   subroutine lookup_timer(self, name, id, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out) :: id
      integer, intent(out), optional :: ierr
      integer :: idx
      integer :: trimmed_len
      integer :: status
      character(len=:), allocatable :: message

      id = 0

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp lookup_timer before init")
         return
      end if

      call normalize_name(name, trimmed_len, status, message)
      if (status /= FTIMER_SUCCESS) then
         call report_timer_status(self, ierr, status, message)
         return
      end if

      idx = find_timer_index(self, name(1:trimmed_len))
      if (idx <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp lookup_timer with unknown timer name")
         return
      end if

      id = self%catalog(idx)%id
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine lookup_timer

   subroutine begin_parallel_region(self, region, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_parallel_region_t), intent(inout) :: region
      integer, intent(out), optional :: ierr

      call clear_region(region)

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp begin_parallel_region before init")
         return
      end if

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp begin_parallel_region called inside an OpenMP parallel region")
         return
      end if

      if (self%region_open) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp begin_parallel_region with another region already open")
         return
      end if

      call report_timer_status(self, ierr, FTIMER_ERR_NOT_IMPLEMENTED, &
                               "ftimer_openmp timed parallel regions are not implemented yet")
   end subroutine begin_parallel_region

   subroutine end_parallel_region(self, region, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      type(ftimer_openmp_parallel_region_t), intent(inout) :: region
      integer, intent(out), optional :: ierr

      if (.not. self%initialized) then
         call clear_region(region)
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp end_parallel_region before init")
         return
      end if

      if (is_inside_parallel_region()) then
         call report_timer_status(self, ierr, FTIMER_ERR_ACTIVE, &
                                  "ftimer_openmp end_parallel_region called inside an OpenMP parallel region")
         return
      end if

      call clear_region(region)
      call report_timer_status(self, ierr, FTIMER_ERR_NOT_IMPLEMENTED, &
                               "ftimer_openmp timed parallel regions are not implemented yet")
   end subroutine end_parallel_region

   subroutine start_id(self, id, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp start_id before init")
         return
      end if

      if (find_timer_id_index(self, id) <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp start_id with unknown timer id")
         return
      end if

      call report_timer_status(self, ierr, FTIMER_ERR_NOT_IMPLEMENTED, "ftimer_openmp worker timing is not implemented yet")
   end subroutine start_id

   subroutine stop_id(self, id, ierr)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: id
      integer, intent(out), optional :: ierr

      if (.not. self%initialized) then
         call report_timer_status(self, ierr, FTIMER_ERR_NOT_INIT, "ftimer_openmp stop_id before init")
         return
      end if

      if (find_timer_id_index(self, id) <= 0) then
         call report_timer_status(self, ierr, FTIMER_ERR_UNKNOWN, "ftimer_openmp stop_id with unknown timer id")
         return
      end if

      call report_timer_status(self, ierr, FTIMER_ERR_NOT_IMPLEMENTED, "ftimer_openmp worker timing is not implemented yet")
   end subroutine stop_id

   subroutine clear_state(self)
      class(ftimer_openmp_t), intent(inout) :: self

      self%initialized = .false.
      self%config = ftimer_openmp_config_t()
      if (allocated(self%catalog)) deallocate (self%catalog)
      self%num_timers = 0
      self%region_open = .false.
      self%current_epoch = 0
      self%next_epoch = 1
      call clear_worker_diagnostics(self)
#ifdef FTIMER_USE_MPI
      self%mpi_comm_was_present = .false.
#endif
   end subroutine clear_state

   subroutine clear_region(region)
      type(ftimer_openmp_parallel_region_t), intent(inout) :: region

      region%epoch = 0
      region%active = .false.
   end subroutine clear_region

   logical function normalize_config(config) result(is_valid)
      type(ftimer_openmp_config_t), intent(inout) :: config

      is_valid = .false.

      if (config%mode /= FTIMER_OPENMP_MODE_THREAD_LANES) return
      if (config%max_lanes < 0) return
      if (config%max_worker_diagnostics < 0) return

      if (config%max_lanes == 0) config%max_lanes = default_max_lanes()
      if (config%max_lanes < 1) return

      is_valid = .true.
   end function normalize_config

   integer function default_max_lanes() result(max_lanes)
#ifdef FTIMER_USE_OPENMP
      max_lanes = 1 + omp_get_max_threads()
#else
      max_lanes = 1
#endif
   end function default_max_lanes

   logical function is_inside_parallel_region() result(inside)
#ifdef FTIMER_USE_OPENMP
      inside = omp_in_parallel()
#else
      inside = .false.
#endif
   end function is_inside_parallel_region

   subroutine normalize_name(name, trimmed_len, status, message)
      character(len=*), intent(in) :: name
      integer, intent(out) :: trimmed_len
      integer, intent(out) :: status
      character(len=:), allocatable, intent(out) :: message
      integer :: code
      integer :: i
      character(len=32) :: position_text

      trimmed_len = len_trim(name)

      if (trimmed_len <= 0) then
         status = FTIMER_ERR_INVALID_NAME
         message = "ftimer_openmp timer name must not be empty"
         return
      end if

      if (name(1:1) == ' ') then
         status = FTIMER_ERR_INVALID_NAME
         message = "ftimer_openmp timer name must not begin with whitespace"
         return
      end if

      do i = 1, trimmed_len
         code = iachar(name(i:i))
         if ((code < 32) .or. (code == 127)) then
            status = FTIMER_ERR_INVALID_NAME
            write (position_text, '(i0)') i
            message = "ftimer_openmp timer name contains control character at position "//trim(position_text)
            return
         end if
      end do

      status = FTIMER_SUCCESS
   end subroutine normalize_name

   subroutine ensure_catalog_capacity(self, required_size)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: required_size
      type(ftimer_openmp_catalog_entry_t), allocatable :: old_catalog(:)
      integer :: new_size

      if (allocated(self%catalog)) then
         if (size(self%catalog) >= required_size) return
         call move_alloc(self%catalog, old_catalog)
         new_size = max(required_size, 2*size(old_catalog))
         allocate (self%catalog(new_size))
         if (self%num_timers > 0) self%catalog(1:self%num_timers) = old_catalog(1:self%num_timers)
      else
         new_size = max(required_size, FTIMER_OPENMP_CATALOG_INITIAL_CAPACITY)
         allocate (self%catalog(new_size))
      end if
   end subroutine ensure_catalog_capacity

   integer function allocate_timer_id(self) result(id)
      class(ftimer_openmp_t), intent(inout) :: self

      if (self%next_timer_id <= 0) then
         id = 0
         return
      end if

      id = self%next_timer_id
      if (self%next_timer_id == huge(self%next_timer_id)) then
         self%next_timer_id = -1
      else
         self%next_timer_id = self%next_timer_id + 1
      end if
   end function allocate_timer_id

   integer function find_timer_index(self, name) result(idx)
      class(ftimer_openmp_t), intent(in) :: self
      character(len=*), intent(in) :: name
      integer :: i

      idx = 0
      if (.not. allocated(self%catalog)) return

      do i = 1, self%num_timers
         if (allocated(self%catalog(i)%name)) then
            if (self%catalog(i)%name == name) then
               idx = i
               return
            end if
         end if
      end do
   end function find_timer_index

   integer function find_timer_id_index(self, id) result(idx)
      class(ftimer_openmp_t), intent(in) :: self
      integer, intent(in) :: id
      integer :: i

      idx = 0
      if ((id <= 0) .or. (.not. allocated(self%catalog))) return

      do i = 1, self%num_timers
         if (self%catalog(i)%id == id) then
            idx = i
            return
         end if
      end do
   end function find_timer_id_index

   subroutine clear_worker_diagnostics(self)
      class(ftimer_openmp_t), intent(inout) :: self

      self%queued_worker_diagnostics = 0
      self%worker_diagnostic_overflow = 0
      self%first_worker_status = FTIMER_SUCCESS
   end subroutine clear_worker_diagnostics

   subroutine queue_worker_diagnostic(self, code)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(in) :: code

#ifdef FTIMER_USE_OPENMP
!$omp critical(ftimer_openmp_worker_diagnostics)
#endif
      if (self%first_worker_status == FTIMER_SUCCESS) self%first_worker_status = code
      if (self%queued_worker_diagnostics < self%config%max_worker_diagnostics) then
         self%queued_worker_diagnostics = self%queued_worker_diagnostics + 1
      else
         self%worker_diagnostic_overflow = self%worker_diagnostic_overflow + 1
      end if
#ifdef FTIMER_USE_OPENMP
!$omp end critical(ftimer_openmp_worker_diagnostics)
#endif
   end subroutine queue_worker_diagnostic

   subroutine emit_worker_diagnostics(self)
      class(ftimer_openmp_t), intent(inout) :: self

      if ((self%queued_worker_diagnostics <= 0) .and. (self%worker_diagnostic_overflow <= 0)) return

      write (error_unit, '(a,i0,a,i0,a,i0)') "ftimer_openmp recorded ", &
         self%queued_worker_diagnostics, " worker diagnostics; first status ", &
         self%first_worker_status, ", overflow ", self%worker_diagnostic_overflow
      call clear_worker_diagnostics(self)
   end subroutine emit_worker_diagnostics

   subroutine report_timer_status(self, ierr, code, message)
      class(ftimer_openmp_t), intent(inout) :: self
      integer, intent(out), optional :: ierr
      integer, intent(in) :: code
      character(len=*), intent(in) :: message

      if (present(ierr)) then
         ierr = code
      elseif (is_inside_parallel_region()) then
         call queue_worker_diagnostic(self, code)
      else
         call emit_worker_diagnostics(self)
         write (error_unit, '(a)') trim(message)
      end if
   end subroutine report_timer_status

end module ftimer_openmp
