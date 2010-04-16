class Game
  PIECE_SIZE = 35 #pixels
  PIECE_SCALE_FACTOR = 0.8333333 #so the pieces don't take up the full "square" allocated to them
  BOARD_WIDTH = 8 #width of board in pieces
  BOARD_HEIGHT = 8
  TIME_ALLOWED = 30 #starting value for seconds remaining in timed mode
  TIME_GAIN_PER_PIECE = 1 #seconds gained per piece removed in timed mode
  HIGH_SCORES_FILE = "beshoelled_high_scores.txt"
  UPDATE_SPEED = 8 #updates per second
  ANIMATE_SPEED = 45 #redraws per second
  attr_accessor :board, :score, :high_score, :timed_high_score, :game_over, :time_remaining
  
  def initialize
    new_game(false)   
  end
  
  def new_game(timer)
    $game = self
    
    #get previous high scores, if any
    if File.exist?(HIGH_SCORES_FILE)
      File.open(HIGH_SCORES_FILE, "r").read.each do |line|
          line = line.split(/,/)
          @high_score = line[0].to_i
          @timed_high_score = line[1].to_i
        end
    else
      @high_score = 0
      @timed_high_score = 0
    end
        
    @score = 0
    @board = Board.new
    @game_over = false
    @time_remaining = nil
    if timer
      @time_remaining = TIME_ALLOWED
      start_timer
    end    
    start_update
    start_anim
  end
  
  #update the score after a move has resolved
  def adjust_score(pieces)
    #score increase by 10 + the number pieces removed in a given move
    @score += pieces + 10
    #in timed mode, gain one second per piece removed
    if @time_remaining
      @time_remaining += pieces * TIME_GAIN_PER_PIECE
    end
   
   #find and write the new high score if applicable
   if(@score > @high_score and @time_remaining.nil?)
     @high_score = @score
   end   
   if(@score > @timed_high_score and !@time_remaining.nil?)
     @timed_high_score = @score
   end

   f = File.open(HIGH_SCORES_FILE, "w+")
   f.write("#{@high_score},#{@timed_high_score}")
   f.close
  end
  
  #update the game state, doing match clearing, piece-dropping, score adjusting and game-over-ing as required
  def update
    if @board.recheck
      #@board.compact_pieces
      @board.clear_matches
    elsif @board.pieces_removed != 0
      adjust_score(@board.pieces_removed)
      @board.pieces_removed = 0  
      #end game if no legal moves left      
      if not @board.any_moves?
        stop_anim
        stop_update
        stop_timer
        @game_over = true
        draw
        $app.alert("Game over: no more moves")
      end 
    end
    #end game if out of time
    if @time_remaining && (@time_remaining < 0)
      stop_anim
      stop_update
      stop_timer
      @game_over = true
      draw
      $app.alert("Game over: out of time.")  
    end
  end
  
  #draws everything
  def draw
    $app.clear
    
    #draw the board/pieces
    @board.draw
    
    #draw the various text bits
    $app.para("Score: #{@score}")
    if(@time_remaining.nil?)
      $app.inscription("(High: #{@high_score})")
    else
      $app.inscription("(High: #{@timed_high_score})")
    end
    
    @new_game_text = $app.para("New Game")
    @new_game_text.top = PIECE_SIZE * (BOARD_HEIGHT + 2)
    @new_game_text.left = PIECE_SIZE
    
    @new_timed_game_text = $app.para("New Timed Game")
    @new_timed_game_text.top = PIECE_SIZE * (BOARD_HEIGHT + 2)
    @new_timed_game_text.left = (PIECE_SIZE * BOARD_WIDTH/2) + PIECE_SIZE
    
    if(@time_remaining)
      @timer_text = $app.para("Time left: #{@time_remaining}")
      @timer_text.left = 6.5 * PIECE_SIZE
    end
  end
  
  #start the loop that draws everything
  def start_anim
    @drawing = $app.animate(ANIMATE_SPEED) do
      draw
    end
  end
  
  #start the loop that updates the game state
  def start_update   
    @updating = $app.animate(UPDATE_SPEED) do
      update
    end
  end
  
  #start the timer, for timed mode
  def start_timer
    @timing = $app.animate(1) do
      @time_remaining -= 1
    end
  end
  
  def stop_anim
    @drawing.remove unless @drawing.nil?
  end
  
  def stop_update
    @updating.remove unless @updating.nil?
  end
  
  def stop_timer
    @timing.remove unless @timing.nil?
  end
  
end

class Board  
  attr_accessor :board, :pieces_removed, :recheck
  
  def initialize
    @width = Game::BOARD_WIDTH
    @height = Game::BOARD_HEIGHT
    #the board is a 2D array of pieces
    @board = Array.new(@width){Array.new(@height){nil}}
    @selected_piece = nil
    @pieces_removed = 0
    @recheck = true    
    setup_board    
  end
  
  #fills the board with random pieces then clears any matches so that the start position is stable
  def setup_board
    @startup = true
    @board = @board.map{|col| col.map{|piece| Piece.new if piece.nil?}}
    clear_matches
    @startup = false
    @pieces_removed = 0
  end
  
  #draw the pieces
  def draw
    for i in (0..@width-1)
      for j in (0..@height-1)
        @board[i][j].draw(i,j) unless @board[i][j].nil? or @board[i][j] == @selected_piece
        if @board[i][j] == @selected_piece and !@selected_piece.nil? then @board[i][j].draw_selected(i,j) end
      end
    end
  end
  
  def clear_matches
    check_matches
    remove_marked
    compact_pieces
  end
   
  #checks if any 3-in-a-row or greater matches have been made, and marks all matching pieces for later removal
  def check_matches
   #check for horizontal matches
    match_found = false          
    for i in (0..@width-3)
      for j in (0..@height-1)
        if (@board[i][j] and @board[i+1][j] and @board[i+2][j] and 
              @board[i][j].color == @board[i+1][j].color and @board[i][j].color == @board[i+2][j].color)
          @board[i][j].marked = @board[i+1][j].marked = @board[i+2][j].marked = true
          match_found = true
        end
      end
    end
     #check for vertical matches
     for i in (0..@width-1)
      for j in (0..@height-3)
        if (@board[i][j] and @board[i][j+1] and @board[i][j+2] and 
          @board[i][j].color == @board[i][j+1].color and @board[i][j].color == @board[i][j+2].color)
          @board[i][j].marked = @board[i][j+1].marked = @board[i][j+2].marked = true
          match_found = true
        end
      end
    end

    return match_found    
  end
  
  def unmark_all
    for i in (0..@width-1)
      for j in (0..@height-1)
        if @board[i][j] and @board[i][j].marked
          @board[i][j].marked = false
        end
      end
    end
  end
  
  #remove the pieces that were marked as being part of a match
  def remove_marked
    for i in (0..@width-1)
      for j in (0..@height-1)
        if @board[i][j] and @board[i][j].marked
          @board[i][j] = nil
          @pieces_removed += 1
        end
      end
    end
  end
  
  #drops pieces down, checking for any new matches formed
  def compact_pieces
    @recheck = false
    for i in (0..@width-1)
      for j in (0..@height-1)
        if @board[i][j] and @board[i][j+1].nil? #drop pieces down
          @recheck = true
          @board[i][j+1] = @board[i][j]
          @board[i][j] = nil 
        elsif j == 0 and @board[i][j].nil? #replace pieces at top
          @recheck = true
          @board[i][j] = Piece.new
        end
      end
    end
    if @startup and @recheck #fast setup of board before update + anim loops start
      compact_pieces
      clear_matches
    end 
  end
  
  def select_piece(x, y)
    if @pieces_removed == 0 #wait for one move to finish before allowing the next
      if @selected_piece.nil?
        @selected_piece = @board[x][y]
        @selected_piece.draw_selected(x,y)
      else       
        if((x + y - @selected_piece.sum_of_coords).abs == 1) #only allow horizontal or vertical adjacent swaps
          swap_pieces(@selected_piece, @board[x][y])
        else
          @selected_piece = nil
        end      
      end   
    end
  end
  
  #swaps the selected piece with the next piece that was (validly) clicked on
  def swap_pieces(piece1, piece2)
    piece1.color, piece2.color = piece2.color, piece1.color
    @selected_piece = nil
    unless check_matches
      #revert if not a match-completing (ie legal) move
      piece2.color, piece1.color = piece1.color, piece2.color 
    end
    clear_matches   
  end

  #check if there are any legal moves left by trying all possible moves
  def any_moves?
    #try all horiz swaps
    for i in (0..@width-2)
      for j in (0..@height-1)
        #swap and see if a match is made
        @board[i][j].color, @board[i+1][j].color = @board[i+1][j].color, @board[i][j].color    
        if check_matches
          unmark_all
          #undo swap
          @board[i][j].color, @board[i+1][j].color = @board[i+1][j].color, @board[i][j].color 
          return true
        else
          #undo swap regardless
          @board[i][j].color, @board[i+1][j].color = @board[i+1][j].color, @board[i][j].color 
        end
      end
    end
    #try all vert swaps
    for i in (0..@width-1) 
      for j in (0..@height-2)
        @board[i][j].color, @board[i][j+1].color = @board[i][j+1].color, @board[i][j].color
        if check_matches
          unmark_all
          @board[i][j].color, @board[i][j+1].color = @board[i][j+1].color, @board[i][j].color
          return true
        else
          @board[i][j].color, @board[i][j+1].color = @board[i][j+1].color, @board[i][j].color
        end
      end
    end    
    
    return false #no move was found  
  end
  
end

class Piece
  attr_accessor :marked, :color, :x, :y, :number
  COLORS = [$app.rgb(255, 190, 0), $app.rgb(30, 191, 255), $app.rgb(34, 139, 34), 
    $app.rgb(255, 20, 147), $app.rgb(123, 255, 17),
    $app.rgb(255, 0, 0), $app.rgb(69, 0, 255)]
  
  def initialize
    @color = COLORS[rand(COLORS.length)] #one of the 7 colors is assigned at random to each piece on creation
    @marked = false
    @x = 0
    @y = 0
	@number = 1 + rand(7)
  end

  #piece draws itself in the supplied position
  def draw(x_position, y_position)
    $app.fill(rgb(255,255,255))
	$app.title(@number)
    #$app.oval(x_position * Game::PIECE_SIZE + Game::PIECE_SIZE, y_position * Game::PIECE_SIZE + Game::PIECE_SIZE, 
     # Game::PIECE_SIZE * Game::PIECE_SCALE_FACTOR)
    #update the coordinates of the piece
    @x = x_position
    @y = y_position
  end
  
  #same as draw but with a red outline, for the currently selected piece
  def draw_selected(x_position, y_position)
    $app.stroke($app.rgb(255,0,0))
    draw(x_position, y_position)
    $app.stroke($app.rgb(0,0,0))
  end
  
  def sum_of_coords
    return @x + @y
  end

end

Shoes.app(
  :title => "Beshoelled", 
  :width => Game::PIECE_SIZE * (Game::BOARD_WIDTH + 2), 
  :height => Game::PIECE_SIZE * (Game::BOARD_HEIGHT + 3), 
  :resizable => true
  ) do
    
  $app = self
  
  background white
  $game = Game.new
  
   
  click do |button, x, y|
     #handle when the player clicks on a piece
     if(x < Game::PIECE_SIZE * (Game::BOARD_WIDTH + 1) && y < Game::PIECE_SIZE * (Game::BOARD_HEIGHT + 1) && 
           x > Game::PIECE_SIZE && y > Game::PIECE_SIZE && !$game.game_over)
       x_coord = x/Game::PIECE_SIZE - 1
       y_coord = y/Game::PIECE_SIZE - 1
       $game.board.select_piece(x_coord, y_coord)
     end     
     
     #start a new untimed game when clicking near the text - causing intermittent crash of shoes when clicked
     if(x < Game::PIECE_SIZE * (Game::BOARD_WIDTH + 2)/2.2 && y > Game::PIECE_SIZE * (Game::BOARD_HEIGHT + 1.5))
      $game.stop_anim
      $game.stop_update
      $game.stop_timer
      $game.new_game(false) #start a new untimed game
     end
     #start a new timed game when clicking near the text - also crashes sometimes
     if(x > Game::PIECE_SIZE * (Game::BOARD_WIDTH + 2)/2.2 && y > Game::PIECE_SIZE * (Game::BOARD_HEIGHT + 1.5))
      $game.stop_anim
      $game.stop_update
      $game.stop_timer
      $game.new_game(true) #start a new timed game
     end    
  end
 end