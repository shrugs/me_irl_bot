class Iterator
  def initialize(arr = [])
    @arr = arr
    @i = 0
  end

  def next
    return nil if @arr.length == 0
    r = @arr[@i]
    @i = (@i + 1) % @arr.length
    return r
  end
end
