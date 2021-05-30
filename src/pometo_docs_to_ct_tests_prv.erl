-module(pometo_docs_to_ct_tests_prv).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, pometo_docs_to_ct_tests).
-define(DEPS, [app_discovery]).

-define(IN_TEXT,        1).
-define(GETTING_TEST,   2).
-define(GETTING_RESULT, 3).
-define(GETTING_LAZY,   4).

-define(SPACE, 32).
-define(UNDERSCORE, 95).

-record(test, {
							 seq          = 0,
							 title        = "",
							 codeacc      = [],
							 resultsacc   = [],
							 lazyacc      = [],
							 stashedtitle = ""
		}).

%% ===================================================================
%% Public API
%% ===================================================================
-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
		Provider = providers:create([
						{name,       ?PROVIDER},                        % The 'user friendly' name of the task
						{module,     ?MODULE},                          % The module implementation of the task
						{bare,       true},                             % The task can be run by the user, always true
						{deps,       ?DEPS},                            % The list of dependencies
						{example,    "rebar3 pometo_docs_to_ct_tests"}, % How to use the plugin
						{opts,       []},                               % list of options understood by the plugin
						{short_desc, "Builds common tests from pometo markdown documentation."},
						{desc,       "Builds common tests from pometo markdown documentation.\n" ++
												 "For each pair of marked up code snippets 6 distinct code path tests will be generated.\n" ++
												 "There is an option for having different results for lazy evaluation (Error results differ in the lazy case/\n" ++
												 "Work In Progress docs are excluded by default but can be built using an environment variable.\n" ++
												 "See https://gordonguthrie.github.io/pometo/implementation_reference/getting_started_as_a_developer_of_the_pometo_runtime_and_language.html#how-to-write-docs-pages-as-tests"}
		]),
		{ok, rebar_state:add_provider(State, Provider)}.


-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
		lists:foreach(fun make_tests/1, rebar_state:project_apps(State)),
		{ok, State}.

-spec format_error(any()) ->  iolist().
format_error(Reason) ->
		io_lib:format("~p", [Reason]).

make_tests(App) ->
		BuildWIP = os:getenv("BUILDWIP"),
		case BuildWIP of
				false -> io:format("not building WIP tests~n");
				_True -> io:format("%%%%%%%%%%%%%%%%%%%%%%\n"
													 "% building WIP Tests %\n"
													 "%%%%%%%%%%%%%%%%%%%%%%\n")
		end,

		Root = rebar_app_info:dir(App),
		GeneratedTestDir = filename:join([Root, "test", "generated_common_tests"]),
		case filelib:is_dir(GeneratedTestDir) of
			true  -> io:format("* deleting the generated test directory ~p~n", [GeneratedTestDir]),
							 ok = del_dir(GeneratedTestDir);
			false -> ok
		end,
		ok = file:make_dir(GeneratedTestDir),
		DocsFiles = lists:flatten(get_files(filename:join([Root, "docs", "*"]))),
		[generate_tests(X, GeneratedTestDir) || {X} <- DocsFiles],
		ok.

get_files(Root) ->
		RawFiles = filelib:wildcard(Root),
		io:format("Rawfiles is ~p~n", [RawFiles]),
		Files     = [{X} || X <- RawFiles, filename:extension(X) == ".md"],
		Dirs      = [X   || X <- RawFiles, filelib:is_dir(X),
																			 filename:basename(X) /= "_site",
																			 filename:basename(X) /= "_data",
																			 filename:basename(X) /= "_layouts",
																			 filename:basename(X) /= "assets",
																			 filename:basename(X) /= "images"],
		BuildWIP = os:getenv("BUILDWIP"),
		Dirs2 = case BuildWIP of
				false -> [filename:join(X, "*") || X <- Dirs, filename:basename(X) /= "_work_in_progress"];
				_True -> [filename:join(X, "*") || X <- Dirs]
		end,
		DeepFiles = [get_files(X) || X <- Dirs2],
		[Files ++ lists:flatten(DeepFiles)].

generate_tests([], _GeneratedTestDir) -> ok;
generate_tests(File, GeneratedTestDir) ->
		{ok, Lines} = read_lines(File),
		Basename = filename:basename(File, ".md"),
		FileName = Basename ++ "_SUITE",
		gen_test2(FileName, Lines, GeneratedTestDir),
		ok.

gen_test2(Filename, Lines, GeneratedTestDir) ->
		{All, Body} = gen_test3(Lines, ?IN_TEXT, #test{}, [], []),
		io:format("in gen_test2 All is ~p~n", [All]),
		case Body of
				[] -> ok;
				_  -> io:format("* writing test ~p~n", [Filename ++ ".erl"]),
							Disclaimer = "%%% DO NOT EDIT this test suite is generated by the pometo_docs_to_ct_test rebar3 plugin\n\n",
							Header     = "-module(" ++ Filename ++ ").\n\n",
							Include    = "-include_lib(\"eunit/include/eunit.hrl\").\n\n",
							Export     = "-compile([export_all]).\n\n",
							Module = Disclaimer ++ Header ++ Include ++ Export ++ Body,
							DirAndFile = string:join([GeneratedTestDir, Filename ++ ".erl"], "/"),
							ok = file:write_file(DirAndFile, Module)
		end,
		ok.

gen_test3([], _, #test{stashedtitle = NewTitle} = Test, All, Acc) ->
	% there is a problem with the deferred processing of a page
	% this is how we deal with it - we pull the stashed title out and use that
	% on the final walk around the park...
	{_NewTest, NewAcc} = process_test(Test#test{title = NewTitle}, Acc),
	{lists:reverse(All), lists:flatten(lists:reverse(NewAcc))};
gen_test3(["```pometo_results" ++ _Rest | T], ?IN_TEXT, Test, All, Acc) ->
		gen_test3(T, ?GETTING_RESULT, Test, All, Acc);
gen_test3(["```pometo_lazy" ++ _Rest | T], ?IN_TEXT, Test, All, Acc) ->
		gen_test3(T, ?GETTING_LAZY, Test, All, Acc);
gen_test3(["```pometo" ++ _Rest | T], ?IN_TEXT, Test, All, Acc) ->
		{NewTest, NewAcc} = process_test(Test, Acc),
		gen_test3(T, ?GETTING_TEST, NewTest, All, NewAcc);
gen_test3(["```" ++ _Rest | T], _, Test, All, Acc) ->
		gen_test3(T, ?IN_TEXT, Test, All, Acc);
gen_test3([Line | T], ?GETTING_RESULT, Test, All, Acc) ->
		#test{resultsacc = R} = Test,
		gen_test3(T, ?GETTING_RESULT, Test#test{resultsacc = [string:trim(Line, trailing, "\n") | R]}, All, Acc);
gen_test3([Line | T], ?GETTING_LAZY, Test, All, Acc) ->
		#test{lazyacc = R} = Test,
		gen_test3(T, ?GETTING_LAZY, Test#test{lazyacc = [string:trim(Line, trailing, "\n") | R]}, All, Acc);
gen_test3([Line | T], ?GETTING_TEST, Test, All, Acc) ->
		#test{codeacc = C} = Test,
		gen_test3(T, ?GETTING_TEST, Test#test{codeacc = [string:trim(Line, trailing, "\n") | C]}, All, Acc);
gen_test3(["## " ++ Title | T], ?IN_TEXT, Test, All, Acc) ->
		NewTitle = normalise(Title),
		gen_test3(T, ?IN_TEXT, Test#test{title = NewTitle}, [NewTitle | All], Acc);
gen_test3([_H | T], ?IN_TEXT, Test, All, Acc) ->
		gen_test3(T, ?IN_TEXT, Test, All, Acc).

process_test(Test, Acc) ->
	#test{seq          = N,
				title        = Tt,
				codeacc      = C,
				resultsacc   = R,
				lazyacc      = L,
				stashedtitle = St} = Test,
	% we only ocassionally get different lazy results
	At = case Tt of
		[] -> St;
		_  -> Tt
	end,
	case {C, R, L} of
		{[], [], []} ->
			% we have to stash the title
			{#test{seq = N + 1, stashedtitle = Tt}, Acc};
		{_, _, []} ->
			NewTest1 = make_test(St, "interpreter",            integer_to_list(N), lists:reverse(C), lists:reverse(R)),
			NewTest2 = make_test(St, "compiler",               integer_to_list(N), lists:reverse(C), lists:reverse(R)),
			NewTest3 = make_test(St, "compiler_lazy",          integer_to_list(N), lists:reverse(C), lists:reverse(R)),
			NewTest4 = make_test(St, "compiler_indexed",       integer_to_list(N), lists:reverse(C), lists:reverse(R)),
			NewTest5 = make_test(St, "compiler_force_index",   integer_to_list(N), lists:reverse(C), lists:reverse(R)),
			NewTest6 = make_test(St, "compiler_force_unindex", integer_to_list(N), lists:reverse(C), lists:reverse(R)),
			%%% we preserve the title, the sequence number will keep the test name different
			%%% if there isn't another title given anyhoo
			{#test{seq = N + 1, stashedtitle = At}, [NewTest6, NewTest5, NewTest4, NewTest3, NewTest2, NewTest1 | Acc]};
		{_, _, _} ->
			NewTest1 = make_test(St, "interpreter",            integer_to_list(N), lists:reverse(C), lists:reverse(R)),
			NewTest2 = make_test(St, "compiler",               integer_to_list(N), lists:reverse(C), lists:reverse(R)),
			NewTest3 = make_test(St, "compiler_lazy",          integer_to_list(N), lists:reverse(C), lists:reverse(L)),
			NewTest4 = make_test(St, "compiler_indexed",       integer_to_list(N), lists:reverse(C), lists:reverse(R)),
			NewTest5 = make_test(St, "compiler_force_index",   integer_to_list(N), lists:reverse(C), lists:reverse(R)),
			NewTest6 = make_test(St, "compiler_force_unindex", integer_to_list(N), lists:reverse(C), lists:reverse(R)),
			%%% we preserve the title, the sequence number will keep the test name different
			%%% if there isn't another title given anyhoo
			{#test{seq = N + 1, stashedtitle = At}, [NewTest6, NewTest5, NewTest4, NewTest3, NewTest2, NewTest1 | Acc]}
	end.

normalise(Text) ->
		Normalised = norm2(string:to_lower(Text), []),
		case [hd(Normalised)] of
			"_" -> "test" ++ Normalised;
			_   ->           Normalised
	end.

norm2([], Acc) -> lists:reverse(Acc);
norm2([H | T], Acc) when H >= 97 andalso H =< 122 ->
		norm2(T, [H | Acc]);
norm2([?SPACE | T], Acc) ->
		norm2(T, [?UNDERSCORE | Acc]);
norm2([_H | T], Acc) ->
		 norm2(T, Acc).

make_test(Title, Type, Seq, Code, Results) ->
	Title2 = case Title of
		[] -> "anonymous";
		_  -> Title
	end,
	NameRoot = Title2 ++ "_" ++ Seq ++ "_" ++ Type,
	Main = NameRoot ++ "_test_() ->\n" ++
		"    Code     = [\"" ++ string:join(Code,    "\",\n    \"") ++ "\"],\n" ++
		"    Expected = \""  ++ string:join(Results, "\\n\" ++ \n    \"") ++ "\",\n",
	Call = case Type of
		"interpreter" ->
			"    Got = pometo_test_helper:run_" ++ Type ++ "_test(Code),\n";
		"compiler" ->
			"    Got = pometo_test_helper:run_" ++ Type ++ "_test(\"" ++ NameRoot ++ "\", Code),\n";
		"compiler_lazy" ->
			"    Got = pometo_test_helper:run_" ++ Type ++ "_test(\"" ++ NameRoot ++ "\", Code),\n";
		"compiler_force_index" ->
			"    Got = pometo_test_helper:run_" ++ Type ++ "_test(\"" ++ NameRoot ++ "\", Code),\n";
		"compiler_force_unindex" ->
			"    Got = pometo_test_helper:run_" ++ Type ++ "_test(\"" ++ NameRoot ++ "\", Code),\n";
		"compiler_indexed" ->
			"    Got = pometo_test_helper:run_" ++ Type ++ "_test(\"" ++ NameRoot ++ "\", Code),\n"
		end,
	Printing = "    % ?debugFmt(\" in " ++ NameRoot ++ "(" ++ Type ++ ")~nCode:~n~ts~nExp:~n~ts~nGot:~n~ts~n\", [Code, Expected, Got]),\n",
	Assert   = "    ?_assertEqual(Expected, Got).\n\n",
	Main ++ Call ++ Printing ++ Assert.

read_lines(File) ->
		case file:open(File, read) of
				{error, Err} -> {error, Err};
				{ok, Id}     -> read_l2(Id, [])
		end.

read_l2(Id, Acc) ->
		case file:read_line(Id) of
				{ok, Data}   -> read_l2(Id, [Data | Acc]);
				{error, Err} -> {error, Err};
				eof          -> {ok, lists:reverse(Acc)}
		end.

del_dir(Dir) ->
	 lists:foreach(fun(D) ->
										ok = file:del_dir(D)
								 end, del_all_files([Dir], [])).

del_all_files([], EmptyDirs) ->
	 EmptyDirs;
del_all_files([Dir | T], EmptyDirs) ->
	 {ok, FilesInDir} = file:list_dir(Dir),
	 {Files, Dirs} = lists:foldl(fun(F, {Fs, Ds}) ->
																	Path = filename:join([Dir, F]),
																	case filelib:is_dir(Path) of
																		 true ->
																					{Fs, [Path | Ds]};
																		 false ->
																					{[Path | Fs], Ds}
																	end
															 end, {[],[]}, FilesInDir),
	 lists:foreach(fun(F) ->
												 ok = file:delete(F)
								 end, Files),
	 del_all_files(T ++ Dirs, [Dir | EmptyDirs]).
