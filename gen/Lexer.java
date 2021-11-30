// Generated from /home/mesut/Desktop/lang/Lexer.g4 by ANTLR 4.9.1
import org.antlr.v4.runtime.Lexer;
import org.antlr.v4.runtime.CharStream;
import org.antlr.v4.runtime.Token;
import org.antlr.v4.runtime.TokenStream;
import org.antlr.v4.runtime.*;
import org.antlr.v4.runtime.atn.*;
import org.antlr.v4.runtime.dfa.DFA;
import org.antlr.v4.runtime.misc.*;

@SuppressWarnings({"all", "warnings", "unchecked", "unused", "cast"})
public class Lexer extends Lexer {
	static { RuntimeMetaData.checkVersion("4.9.1", RuntimeMetaData.VERSION); }

	protected static final DFA[] _decisionToDFA;
	protected static final PredictionContextCache _sharedContextCache =
		new PredictionContextCache();
	public static final int
		CLASS=1, ENUM=2, INTERFACE=3, IMPORT=4, AS=5, BREAK=6, CASE=7, CONTINUE=8, 
		DO=9, ELSE=10, FOR=11, IF=12, LET=13, RETURN=14, WHILE=15, SWITCH=16, 
		VAR=17, LPAREN=18, RPAREN=19, LBRACE=20, RBRACE=21, LBRACK=22, RBRACK=23, 
		SEMI=24, COMMA=25, DOT=26, ELLIPSIS=27, AT=28, COLONCOLON=29, GT=30, LT=31, 
		BANG=32, TILDE=33, QUESTION=34, COLON=35, ARROW=36, EQUAL=37, LE=38, GE=39, 
		NOTEQUAL=40, AND=41, OR=42, INC=43, DEC=44, ADD=45, SUB=46, MUL=47, DIV=48, 
		BITAND=49, BITOR=50, CARET=51, MOD=52, LSHIFT=53, RSHIFT=54, STARSTAR=55, 
		ASSIGN=56, ADD_ASSIGN=57, SUB_ASSIGN=58, MUL_ASSIGN=59, DIV_ASSIGN=60, 
		AND_ASSIGN=61, OR_ASSIGN=62, XOR_ASSIGN=63, MOD_ASSIGN=64, LSHIFT_ASSIGN=65, 
		RSHIFT_ASSIGN=66, URSHIFT_ASSIGN=67, CHAR=68, BYTE=69, SHORT=70, INT=71, 
		LONG=72, FLOAT=73, DOUBLE=74, BOOLEAN=75, VOID=76, BOOLEAN_LIT=77, NULL_LIT=78, 
		INTEGER_LIT=79, FLOAT_LIT=80, CHAR_LIT=81, STRING_LIT=82, IDENT=83, WS=84, 
		BLOCK_COMMENT=85, LINE_COMMENT=86;
	public static String[] channelNames = {
		"DEFAULT_TOKEN_CHANNEL", "HIDDEN"
	};

	public static String[] modeNames = {
		"DEFAULT_MODE"
	};

	private static String[] makeRuleNames() {
		return new String[] {
			"CLASS", "ENUM", "INTERFACE", "IMPORT", "AS", "BREAK", "CASE", "CONTINUE", 
			"DO", "ELSE", "FOR", "IF", "LET", "RETURN", "WHILE", "SWITCH", "VAR", 
			"LPAREN", "RPAREN", "LBRACE", "RBRACE", "LBRACK", "RBRACK", "SEMI", "COMMA", 
			"DOT", "ELLIPSIS", "AT", "COLONCOLON", "GT", "LT", "BANG", "TILDE", "QUESTION", 
			"COLON", "ARROW", "EQUAL", "LE", "GE", "NOTEQUAL", "AND", "OR", "INC", 
			"DEC", "ADD", "SUB", "MUL", "DIV", "BITAND", "BITOR", "CARET", "MOD", 
			"LSHIFT", "RSHIFT", "STARSTAR", "ASSIGN", "ADD_ASSIGN", "SUB_ASSIGN", 
			"MUL_ASSIGN", "DIV_ASSIGN", "AND_ASSIGN", "OR_ASSIGN", "XOR_ASSIGN", 
			"MOD_ASSIGN", "LSHIFT_ASSIGN", "RSHIFT_ASSIGN", "URSHIFT_ASSIGN", "CHAR", 
			"BYTE", "SHORT", "INT", "LONG", "FLOAT", "DOUBLE", "BOOLEAN", "VOID", 
			"BOOLEAN_LIT", "NULL_LIT", "INTEGER_LIT", "FLOAT_LIT", "CHAR_LIT", "STRING_LIT", 
			"IDENT", "WS", "BLOCK_COMMENT", "LINE_COMMENT"
		};
	}
	public static final String[] ruleNames = makeRuleNames();

	private static String[] makeLiteralNames() {
		return new String[] {
			null, "'class'", "'enum'", "'interface'", "'import'", "'as'", "'break'", 
			"'case'", "'continue'", "'do'", "'else'", "'for'", "'if'", "'let'", "'return'", 
			"'while'", "'switch'", "'var'", "'('", "')'", "'{'", "'}'", "'['", "']'", 
			"';'", "','", "'.'", "'...'", "'@'", "'::'", "'>'", "'<'", "'!'", "'~'", 
			"'?'", "':'", "'=>'", "'=='", "'<='", "'>='", "'!='", "'&&'", "'||'", 
			"'++'", "'--'", "'+'", "'-'", "'*'", "'/'", "'&'", "'|'", "'^'", "'%'", 
			"'<<'", "'>>'", "'**'", "'='", "'+='", "'-='", "'*='", "'/='", "'&='", 
			"'|='", "'^='", "'%='", "'<<='", "'>>='", "'>>>='", "'char'", "'byte'", 
			"'short'", "'int'", "'long'", "'float'", "'double'", null, "'void'", 
			null, "'null'"
		};
	}
	private static final String[] _LITERAL_NAMES = makeLiteralNames();
	private static String[] makeSymbolicNames() {
		return new String[] {
			null, "CLASS", "ENUM", "INTERFACE", "IMPORT", "AS", "BREAK", "CASE", 
			"CONTINUE", "DO", "ELSE", "FOR", "IF", "LET", "RETURN", "WHILE", "SWITCH", 
			"VAR", "LPAREN", "RPAREN", "LBRACE", "RBRACE", "LBRACK", "RBRACK", "SEMI", 
			"COMMA", "DOT", "ELLIPSIS", "AT", "COLONCOLON", "GT", "LT", "BANG", "TILDE", 
			"QUESTION", "COLON", "ARROW", "EQUAL", "LE", "GE", "NOTEQUAL", "AND", 
			"OR", "INC", "DEC", "ADD", "SUB", "MUL", "DIV", "BITAND", "BITOR", "CARET", 
			"MOD", "LSHIFT", "RSHIFT", "STARSTAR", "ASSIGN", "ADD_ASSIGN", "SUB_ASSIGN", 
			"MUL_ASSIGN", "DIV_ASSIGN", "AND_ASSIGN", "OR_ASSIGN", "XOR_ASSIGN", 
			"MOD_ASSIGN", "LSHIFT_ASSIGN", "RSHIFT_ASSIGN", "URSHIFT_ASSIGN", "CHAR", 
			"BYTE", "SHORT", "INT", "LONG", "FLOAT", "DOUBLE", "BOOLEAN", "VOID", 
			"BOOLEAN_LIT", "NULL_LIT", "INTEGER_LIT", "FLOAT_LIT", "CHAR_LIT", "STRING_LIT", 
			"IDENT", "WS", "BLOCK_COMMENT", "LINE_COMMENT"
		};
	}
	private static final String[] _SYMBOLIC_NAMES = makeSymbolicNames();
	public static final Vocabulary VOCABULARY = new VocabularyImpl(_LITERAL_NAMES, _SYMBOLIC_NAMES);

	/**
	 * @deprecated Use {@link #VOCABULARY} instead.
	 */
	@Deprecated
	public static final String[] tokenNames;
	static {
		tokenNames = new String[_SYMBOLIC_NAMES.length];
		for (int i = 0; i < tokenNames.length; i++) {
			tokenNames[i] = VOCABULARY.getLiteralName(i);
			if (tokenNames[i] == null) {
				tokenNames[i] = VOCABULARY.getSymbolicName(i);
			}

			if (tokenNames[i] == null) {
				tokenNames[i] = "<INVALID>";
			}
		}
	}

	@Override
	@Deprecated
	public String[] getTokenNames() {
		return tokenNames;
	}

	@Override

	public Vocabulary getVocabulary() {
		return VOCABULARY;
	}


	public Lexer(CharStream input) {
		super(input);
		_interp = new LexerATNSimulator(this,_ATN,_decisionToDFA,_sharedContextCache);
	}

	@Override
	public String getGrammarFileName() { return "Lexer.g4"; }

	@Override
	public String[] getRuleNames() { return ruleNames; }

	@Override
	public String getSerializedATN() { return _serializedATN; }

	@Override
	public String[] getChannelNames() { return channelNames; }

	@Override
	public String[] getModeNames() { return modeNames; }

	@Override
	public ATN getATN() { return _ATN; }

	public static final String _serializedATN =
		"\3\u608b\ua72a\u8133\ub9ed\u417c\u3be7\u7786\u5964\2X\u0220\b\1\4\2\t"+
		"\2\4\3\t\3\4\4\t\4\4\5\t\5\4\6\t\6\4\7\t\7\4\b\t\b\4\t\t\t\4\n\t\n\4\13"+
		"\t\13\4\f\t\f\4\r\t\r\4\16\t\16\4\17\t\17\4\20\t\20\4\21\t\21\4\22\t\22"+
		"\4\23\t\23\4\24\t\24\4\25\t\25\4\26\t\26\4\27\t\27\4\30\t\30\4\31\t\31"+
		"\4\32\t\32\4\33\t\33\4\34\t\34\4\35\t\35\4\36\t\36\4\37\t\37\4 \t \4!"+
		"\t!\4\"\t\"\4#\t#\4$\t$\4%\t%\4&\t&\4\'\t\'\4(\t(\4)\t)\4*\t*\4+\t+\4"+
		",\t,\4-\t-\4.\t.\4/\t/\4\60\t\60\4\61\t\61\4\62\t\62\4\63\t\63\4\64\t"+
		"\64\4\65\t\65\4\66\t\66\4\67\t\67\48\t8\49\t9\4:\t:\4;\t;\4<\t<\4=\t="+
		"\4>\t>\4?\t?\4@\t@\4A\tA\4B\tB\4C\tC\4D\tD\4E\tE\4F\tF\4G\tG\4H\tH\4I"+
		"\tI\4J\tJ\4K\tK\4L\tL\4M\tM\4N\tN\4O\tO\4P\tP\4Q\tQ\4R\tR\4S\tS\4T\tT"+
		"\4U\tU\4V\tV\4W\tW\3\2\3\2\3\2\3\2\3\2\3\2\3\3\3\3\3\3\3\3\3\3\3\4\3\4"+
		"\3\4\3\4\3\4\3\4\3\4\3\4\3\4\3\4\3\5\3\5\3\5\3\5\3\5\3\5\3\5\3\6\3\6\3"+
		"\6\3\7\3\7\3\7\3\7\3\7\3\7\3\b\3\b\3\b\3\b\3\b\3\t\3\t\3\t\3\t\3\t\3\t"+
		"\3\t\3\t\3\t\3\n\3\n\3\n\3\13\3\13\3\13\3\13\3\13\3\f\3\f\3\f\3\f\3\r"+
		"\3\r\3\r\3\16\3\16\3\16\3\16\3\17\3\17\3\17\3\17\3\17\3\17\3\17\3\20\3"+
		"\20\3\20\3\20\3\20\3\20\3\21\3\21\3\21\3\21\3\21\3\21\3\21\3\22\3\22\3"+
		"\22\3\22\3\23\3\23\3\24\3\24\3\25\3\25\3\26\3\26\3\27\3\27\3\30\3\30\3"+
		"\31\3\31\3\32\3\32\3\33\3\33\3\34\3\34\3\34\3\34\3\35\3\35\3\36\3\36\3"+
		"\36\3\37\3\37\3 \3 \3!\3!\3\"\3\"\3#\3#\3$\3$\3%\3%\3%\3&\3&\3&\3\'\3"+
		"\'\3\'\3(\3(\3(\3)\3)\3)\3*\3*\3*\3+\3+\3+\3,\3,\3,\3-\3-\3-\3.\3.\3/"+
		"\3/\3\60\3\60\3\61\3\61\3\62\3\62\3\63\3\63\3\64\3\64\3\65\3\65\3\66\3"+
		"\66\3\66\3\67\3\67\3\67\38\38\38\39\39\3:\3:\3:\3;\3;\3;\3<\3<\3<\3=\3"+
		"=\3=\3>\3>\3>\3?\3?\3?\3@\3@\3@\3A\3A\3A\3B\3B\3B\3B\3C\3C\3C\3C\3D\3"+
		"D\3D\3D\3D\3E\3E\3E\3E\3E\3F\3F\3F\3F\3F\3G\3G\3G\3G\3G\3G\3H\3H\3H\3"+
		"H\3I\3I\3I\3I\3I\3J\3J\3J\3J\3J\3J\3K\3K\3K\3K\3K\3K\3K\3L\3L\3L\3L\3"+
		"L\3L\3L\3L\3L\3L\3L\5L\u01c1\nL\3M\3M\3M\3M\3M\3N\3N\3N\3N\3N\3N\3N\3"+
		"N\3N\5N\u01d1\nN\3O\3O\3O\3O\3O\3P\6P\u01d9\nP\rP\16P\u01da\3Q\6Q\u01de"+
		"\nQ\rQ\16Q\u01df\3Q\3Q\6Q\u01e4\nQ\rQ\16Q\u01e5\3R\3R\7R\u01ea\nR\fR\16"+
		"R\u01ed\13R\3R\3R\3S\3S\7S\u01f3\nS\fS\16S\u01f6\13S\3S\3S\3T\3T\7T\u01fc"+
		"\nT\fT\16T\u01ff\13T\3U\6U\u0202\nU\rU\16U\u0203\3U\3U\3V\3V\3V\3V\7V"+
		"\u020c\nV\fV\16V\u020f\13V\3V\3V\3V\3V\3V\3W\3W\3W\3W\7W\u021a\nW\fW\16"+
		"W\u021d\13W\3W\3W\5\u01eb\u01f4\u020d\2X\3\3\5\4\7\5\t\6\13\7\r\b\17\t"+
		"\21\n\23\13\25\f\27\r\31\16\33\17\35\20\37\21!\22#\23%\24\'\25)\26+\27"+
		"-\30/\31\61\32\63\33\65\34\67\359\36;\37= ?!A\"C#E$G%I&K\'M(O)Q*S+U,W"+
		"-Y.[/]\60_\61a\62c\63e\64g\65i\66k\67m8o9q:s;u<w=y>{?}@\177A\u0081B\u0083"+
		"C\u0085D\u0087E\u0089F\u008bG\u008dH\u008fI\u0091J\u0093K\u0095L\u0097"+
		"M\u0099N\u009bO\u009dP\u009fQ\u00a1R\u00a3S\u00a5T\u00a7U\u00a9V\u00ab"+
		"W\u00adX\3\2\7\3\2\62;\4\2aac|\5\2\62;aac|\5\2\13\f\16\17\"\"\4\2\f\f"+
		"\17\17\2\u022a\2\3\3\2\2\2\2\5\3\2\2\2\2\7\3\2\2\2\2\t\3\2\2\2\2\13\3"+
		"\2\2\2\2\r\3\2\2\2\2\17\3\2\2\2\2\21\3\2\2\2\2\23\3\2\2\2\2\25\3\2\2\2"+
		"\2\27\3\2\2\2\2\31\3\2\2\2\2\33\3\2\2\2\2\35\3\2\2\2\2\37\3\2\2\2\2!\3"+
		"\2\2\2\2#\3\2\2\2\2%\3\2\2\2\2\'\3\2\2\2\2)\3\2\2\2\2+\3\2\2\2\2-\3\2"+
		"\2\2\2/\3\2\2\2\2\61\3\2\2\2\2\63\3\2\2\2\2\65\3\2\2\2\2\67\3\2\2\2\2"+
		"9\3\2\2\2\2;\3\2\2\2\2=\3\2\2\2\2?\3\2\2\2\2A\3\2\2\2\2C\3\2\2\2\2E\3"+
		"\2\2\2\2G\3\2\2\2\2I\3\2\2\2\2K\3\2\2\2\2M\3\2\2\2\2O\3\2\2\2\2Q\3\2\2"+
		"\2\2S\3\2\2\2\2U\3\2\2\2\2W\3\2\2\2\2Y\3\2\2\2\2[\3\2\2\2\2]\3\2\2\2\2"+
		"_\3\2\2\2\2a\3\2\2\2\2c\3\2\2\2\2e\3\2\2\2\2g\3\2\2\2\2i\3\2\2\2\2k\3"+
		"\2\2\2\2m\3\2\2\2\2o\3\2\2\2\2q\3\2\2\2\2s\3\2\2\2\2u\3\2\2\2\2w\3\2\2"+
		"\2\2y\3\2\2\2\2{\3\2\2\2\2}\3\2\2\2\2\177\3\2\2\2\2\u0081\3\2\2\2\2\u0083"+
		"\3\2\2\2\2\u0085\3\2\2\2\2\u0087\3\2\2\2\2\u0089\3\2\2\2\2\u008b\3\2\2"+
		"\2\2\u008d\3\2\2\2\2\u008f\3\2\2\2\2\u0091\3\2\2\2\2\u0093\3\2\2\2\2\u0095"+
		"\3\2\2\2\2\u0097\3\2\2\2\2\u0099\3\2\2\2\2\u009b\3\2\2\2\2\u009d\3\2\2"+
		"\2\2\u009f\3\2\2\2\2\u00a1\3\2\2\2\2\u00a3\3\2\2\2\2\u00a5\3\2\2\2\2\u00a7"+
		"\3\2\2\2\2\u00a9\3\2\2\2\2\u00ab\3\2\2\2\2\u00ad\3\2\2\2\3\u00af\3\2\2"+
		"\2\5\u00b5\3\2\2\2\7\u00ba\3\2\2\2\t\u00c4\3\2\2\2\13\u00cb\3\2\2\2\r"+
		"\u00ce\3\2\2\2\17\u00d4\3\2\2\2\21\u00d9\3\2\2\2\23\u00e2\3\2\2\2\25\u00e5"+
		"\3\2\2\2\27\u00ea\3\2\2\2\31\u00ee\3\2\2\2\33\u00f1\3\2\2\2\35\u00f5\3"+
		"\2\2\2\37\u00fc\3\2\2\2!\u0102\3\2\2\2#\u0109\3\2\2\2%\u010d\3\2\2\2\'"+
		"\u010f\3\2\2\2)\u0111\3\2\2\2+\u0113\3\2\2\2-\u0115\3\2\2\2/\u0117\3\2"+
		"\2\2\61\u0119\3\2\2\2\63\u011b\3\2\2\2\65\u011d\3\2\2\2\67\u011f\3\2\2"+
		"\29\u0123\3\2\2\2;\u0125\3\2\2\2=\u0128\3\2\2\2?\u012a\3\2\2\2A\u012c"+
		"\3\2\2\2C\u012e\3\2\2\2E\u0130\3\2\2\2G\u0132\3\2\2\2I\u0134\3\2\2\2K"+
		"\u0137\3\2\2\2M\u013a\3\2\2\2O\u013d\3\2\2\2Q\u0140\3\2\2\2S\u0143\3\2"+
		"\2\2U\u0146\3\2\2\2W\u0149\3\2\2\2Y\u014c\3\2\2\2[\u014f\3\2\2\2]\u0151"+
		"\3\2\2\2_\u0153\3\2\2\2a\u0155\3\2\2\2c\u0157\3\2\2\2e\u0159\3\2\2\2g"+
		"\u015b\3\2\2\2i\u015d\3\2\2\2k\u015f\3\2\2\2m\u0162\3\2\2\2o\u0165\3\2"+
		"\2\2q\u0168\3\2\2\2s\u016a\3\2\2\2u\u016d\3\2\2\2w\u0170\3\2\2\2y\u0173"+
		"\3\2\2\2{\u0176\3\2\2\2}\u0179\3\2\2\2\177\u017c\3\2\2\2\u0081\u017f\3"+
		"\2\2\2\u0083\u0182\3\2\2\2\u0085\u0186\3\2\2\2\u0087\u018a\3\2\2\2\u0089"+
		"\u018f\3\2\2\2\u008b\u0194\3\2\2\2\u008d\u0199\3\2\2\2\u008f\u019f\3\2"+
		"\2\2\u0091\u01a3\3\2\2\2\u0093\u01a8\3\2\2\2\u0095\u01ae\3\2\2\2\u0097"+
		"\u01c0\3\2\2\2\u0099\u01c2\3\2\2\2\u009b\u01d0\3\2\2\2\u009d\u01d2\3\2"+
		"\2\2\u009f\u01d8\3\2\2\2\u00a1\u01dd\3\2\2\2\u00a3\u01e7\3\2\2\2\u00a5"+
		"\u01f0\3\2\2\2\u00a7\u01f9\3\2\2\2\u00a9\u0201\3\2\2\2\u00ab\u0207\3\2"+
		"\2\2\u00ad\u0215\3\2\2\2\u00af\u00b0\7e\2\2\u00b0\u00b1\7n\2\2\u00b1\u00b2"+
		"\7c\2\2\u00b2\u00b3\7u\2\2\u00b3\u00b4\7u\2\2\u00b4\4\3\2\2\2\u00b5\u00b6"+
		"\7g\2\2\u00b6\u00b7\7p\2\2\u00b7\u00b8\7w\2\2\u00b8\u00b9\7o\2\2\u00b9"+
		"\6\3\2\2\2\u00ba\u00bb\7k\2\2\u00bb\u00bc\7p\2\2\u00bc\u00bd\7v\2\2\u00bd"+
		"\u00be\7g\2\2\u00be\u00bf\7t\2\2\u00bf\u00c0\7h\2\2\u00c0\u00c1\7c\2\2"+
		"\u00c1\u00c2\7e\2\2\u00c2\u00c3\7g\2\2\u00c3\b\3\2\2\2\u00c4\u00c5\7k"+
		"\2\2\u00c5\u00c6\7o\2\2\u00c6\u00c7\7r\2\2\u00c7\u00c8\7q\2\2\u00c8\u00c9"+
		"\7t\2\2\u00c9\u00ca\7v\2\2\u00ca\n\3\2\2\2\u00cb\u00cc\7c\2\2\u00cc\u00cd"+
		"\7u\2\2\u00cd\f\3\2\2\2\u00ce\u00cf\7d\2\2\u00cf\u00d0\7t\2\2\u00d0\u00d1"+
		"\7g\2\2\u00d1\u00d2\7c\2\2\u00d2\u00d3\7m\2\2\u00d3\16\3\2\2\2\u00d4\u00d5"+
		"\7e\2\2\u00d5\u00d6\7c\2\2\u00d6\u00d7\7u\2\2\u00d7\u00d8\7g\2\2\u00d8"+
		"\20\3\2\2\2\u00d9\u00da\7e\2\2\u00da\u00db\7q\2\2\u00db\u00dc\7p\2\2\u00dc"+
		"\u00dd\7v\2\2\u00dd\u00de\7k\2\2\u00de\u00df\7p\2\2\u00df\u00e0\7w\2\2"+
		"\u00e0\u00e1\7g\2\2\u00e1\22\3\2\2\2\u00e2\u00e3\7f\2\2\u00e3\u00e4\7"+
		"q\2\2\u00e4\24\3\2\2\2\u00e5\u00e6\7g\2\2\u00e6\u00e7\7n\2\2\u00e7\u00e8"+
		"\7u\2\2\u00e8\u00e9\7g\2\2\u00e9\26\3\2\2\2\u00ea\u00eb\7h\2\2\u00eb\u00ec"+
		"\7q\2\2\u00ec\u00ed\7t\2\2\u00ed\30\3\2\2\2\u00ee\u00ef\7k\2\2\u00ef\u00f0"+
		"\7h\2\2\u00f0\32\3\2\2\2\u00f1\u00f2\7n\2\2\u00f2\u00f3\7g\2\2\u00f3\u00f4"+
		"\7v\2\2\u00f4\34\3\2\2\2\u00f5\u00f6\7t\2\2\u00f6\u00f7\7g\2\2\u00f7\u00f8"+
		"\7v\2\2\u00f8\u00f9\7w\2\2\u00f9\u00fa\7t\2\2\u00fa\u00fb\7p\2\2\u00fb"+
		"\36\3\2\2\2\u00fc\u00fd\7y\2\2\u00fd\u00fe\7j\2\2\u00fe\u00ff\7k\2\2\u00ff"+
		"\u0100\7n\2\2\u0100\u0101\7g\2\2\u0101 \3\2\2\2\u0102\u0103\7u\2\2\u0103"+
		"\u0104\7y\2\2\u0104\u0105\7k\2\2\u0105\u0106\7v\2\2\u0106\u0107\7e\2\2"+
		"\u0107\u0108\7j\2\2\u0108\"\3\2\2\2\u0109\u010a\7x\2\2\u010a\u010b\7c"+
		"\2\2\u010b\u010c\7t\2\2\u010c$\3\2\2\2\u010d\u010e\7*\2\2\u010e&\3\2\2"+
		"\2\u010f\u0110\7+\2\2\u0110(\3\2\2\2\u0111\u0112\7}\2\2\u0112*\3\2\2\2"+
		"\u0113\u0114\7\177\2\2\u0114,\3\2\2\2\u0115\u0116\7]\2\2\u0116.\3\2\2"+
		"\2\u0117\u0118\7_\2\2\u0118\60\3\2\2\2\u0119\u011a\7=\2\2\u011a\62\3\2"+
		"\2\2\u011b\u011c\7.\2\2\u011c\64\3\2\2\2\u011d\u011e\7\60\2\2\u011e\66"+
		"\3\2\2\2\u011f\u0120\7\60\2\2\u0120\u0121\7\60\2\2\u0121\u0122\7\60\2"+
		"\2\u01228\3\2\2\2\u0123\u0124\7B\2\2\u0124:\3\2\2\2\u0125\u0126\7<\2\2"+
		"\u0126\u0127\7<\2\2\u0127<\3\2\2\2\u0128\u0129\7@\2\2\u0129>\3\2\2\2\u012a"+
		"\u012b\7>\2\2\u012b@\3\2\2\2\u012c\u012d\7#\2\2\u012dB\3\2\2\2\u012e\u012f"+
		"\7\u0080\2\2\u012fD\3\2\2\2\u0130\u0131\7A\2\2\u0131F\3\2\2\2\u0132\u0133"+
		"\7<\2\2\u0133H\3\2\2\2\u0134\u0135\7?\2\2\u0135\u0136\7@\2\2\u0136J\3"+
		"\2\2\2\u0137\u0138\7?\2\2\u0138\u0139\7?\2\2\u0139L\3\2\2\2\u013a\u013b"+
		"\7>\2\2\u013b\u013c\7?\2\2\u013cN\3\2\2\2\u013d\u013e\7@\2\2\u013e\u013f"+
		"\7?\2\2\u013fP\3\2\2\2\u0140\u0141\7#\2\2\u0141\u0142\7?\2\2\u0142R\3"+
		"\2\2\2\u0143\u0144\7(\2\2\u0144\u0145\7(\2\2\u0145T\3\2\2\2\u0146\u0147"+
		"\7~\2\2\u0147\u0148\7~\2\2\u0148V\3\2\2\2\u0149\u014a\7-\2\2\u014a\u014b"+
		"\7-\2\2\u014bX\3\2\2\2\u014c\u014d\7/\2\2\u014d\u014e\7/\2\2\u014eZ\3"+
		"\2\2\2\u014f\u0150\7-\2\2\u0150\\\3\2\2\2\u0151\u0152\7/\2\2\u0152^\3"+
		"\2\2\2\u0153\u0154\7,\2\2\u0154`\3\2\2\2\u0155\u0156\7\61\2\2\u0156b\3"+
		"\2\2\2\u0157\u0158\7(\2\2\u0158d\3\2\2\2\u0159\u015a\7~\2\2\u015af\3\2"+
		"\2\2\u015b\u015c\7`\2\2\u015ch\3\2\2\2\u015d\u015e\7\'\2\2\u015ej\3\2"+
		"\2\2\u015f\u0160\7>\2\2\u0160\u0161\7>\2\2\u0161l\3\2\2\2\u0162\u0163"+
		"\7@\2\2\u0163\u0164\7@\2\2\u0164n\3\2\2\2\u0165\u0166\7,\2\2\u0166\u0167"+
		"\7,\2\2\u0167p\3\2\2\2\u0168\u0169\7?\2\2\u0169r\3\2\2\2\u016a\u016b\7"+
		"-\2\2\u016b\u016c\7?\2\2\u016ct\3\2\2\2\u016d\u016e\7/\2\2\u016e\u016f"+
		"\7?\2\2\u016fv\3\2\2\2\u0170\u0171\7,\2\2\u0171\u0172\7?\2\2\u0172x\3"+
		"\2\2\2\u0173\u0174\7\61\2\2\u0174\u0175\7?\2\2\u0175z\3\2\2\2\u0176\u0177"+
		"\7(\2\2\u0177\u0178\7?\2\2\u0178|\3\2\2\2\u0179\u017a\7~\2\2\u017a\u017b"+
		"\7?\2\2\u017b~\3\2\2\2\u017c\u017d\7`\2\2\u017d\u017e\7?\2\2\u017e\u0080"+
		"\3\2\2\2\u017f\u0180\7\'\2\2\u0180\u0181\7?\2\2\u0181\u0082\3\2\2\2\u0182"+
		"\u0183\7>\2\2\u0183\u0184\7>\2\2\u0184\u0185\7?\2\2\u0185\u0084\3\2\2"+
		"\2\u0186\u0187\7@\2\2\u0187\u0188\7@\2\2\u0188\u0189\7?\2\2\u0189\u0086"+
		"\3\2\2\2\u018a\u018b\7@\2\2\u018b\u018c\7@\2\2\u018c\u018d\7@\2\2\u018d"+
		"\u018e\7?\2\2\u018e\u0088\3\2\2\2\u018f\u0190\7e\2\2\u0190\u0191\7j\2"+
		"\2\u0191\u0192\7c\2\2\u0192\u0193\7t\2\2\u0193\u008a\3\2\2\2\u0194\u0195"+
		"\7d\2\2\u0195\u0196\7{\2\2\u0196\u0197\7v\2\2\u0197\u0198\7g\2\2\u0198"+
		"\u008c\3\2\2\2\u0199\u019a\7u\2\2\u019a\u019b\7j\2\2\u019b\u019c\7q\2"+
		"\2\u019c\u019d\7t\2\2\u019d\u019e\7v\2\2\u019e\u008e\3\2\2\2\u019f\u01a0"+
		"\7k\2\2\u01a0\u01a1\7p\2\2\u01a1\u01a2\7v\2\2\u01a2\u0090\3\2\2\2\u01a3"+
		"\u01a4\7n\2\2\u01a4\u01a5\7q\2\2\u01a5\u01a6\7p\2\2\u01a6\u01a7\7i\2\2"+
		"\u01a7\u0092\3\2\2\2\u01a8\u01a9\7h\2\2\u01a9\u01aa\7n\2\2\u01aa\u01ab"+
		"\7q\2\2\u01ab\u01ac\7c\2\2\u01ac\u01ad\7v\2\2\u01ad\u0094\3\2\2\2\u01ae"+
		"\u01af\7f\2\2\u01af\u01b0\7q\2\2\u01b0\u01b1\7w\2\2\u01b1\u01b2\7d\2\2"+
		"\u01b2\u01b3\7n\2\2\u01b3\u01b4\7g\2\2\u01b4\u0096\3\2\2\2\u01b5\u01b6"+
		"\7d\2\2\u01b6\u01b7\7q\2\2\u01b7\u01b8\7q\2\2\u01b8\u01b9\7n\2\2\u01b9"+
		"\u01ba\7g\2\2\u01ba\u01bb\7c\2\2\u01bb\u01c1\7p\2\2\u01bc\u01bd\7d\2\2"+
		"\u01bd\u01be\7q\2\2\u01be\u01bf\7q\2\2\u01bf\u01c1\7n\2\2\u01c0\u01b5"+
		"\3\2\2\2\u01c0\u01bc\3\2\2\2\u01c1\u0098\3\2\2\2\u01c2\u01c3\7x\2\2\u01c3"+
		"\u01c4\7q\2\2\u01c4\u01c5\7k\2\2\u01c5\u01c6\7f\2\2\u01c6\u009a\3\2\2"+
		"\2\u01c7\u01c8\7v\2\2\u01c8\u01c9\7t\2\2\u01c9\u01ca\7w\2\2\u01ca\u01d1"+
		"\7g\2\2\u01cb\u01cc\7h\2\2\u01cc\u01cd\7c\2\2\u01cd\u01ce\7n\2\2\u01ce"+
		"\u01cf\7u\2\2\u01cf\u01d1\7g\2\2\u01d0\u01c7\3\2\2\2\u01d0\u01cb\3\2\2"+
		"\2\u01d1\u009c\3\2\2\2\u01d2\u01d3\7p\2\2\u01d3\u01d4\7w\2\2\u01d4\u01d5"+
		"\7n\2\2\u01d5\u01d6\7n\2\2\u01d6\u009e\3\2\2\2\u01d7\u01d9\t\2\2\2\u01d8"+
		"\u01d7\3\2\2\2\u01d9\u01da\3\2\2\2\u01da\u01d8\3\2\2\2\u01da\u01db\3\2"+
		"\2\2\u01db\u00a0\3\2\2\2\u01dc\u01de\t\2\2\2\u01dd\u01dc\3\2\2\2\u01de"+
		"\u01df\3\2\2\2\u01df\u01dd\3\2\2\2\u01df\u01e0\3\2\2\2\u01e0\u01e1\3\2"+
		"\2\2\u01e1\u01e3\7\60\2\2\u01e2\u01e4\t\2\2\2\u01e3\u01e2\3\2\2\2\u01e4"+
		"\u01e5\3\2\2\2\u01e5\u01e3\3\2\2\2\u01e5\u01e6\3\2\2\2\u01e6\u00a2\3\2"+
		"\2\2\u01e7\u01eb\7)\2\2\u01e8\u01ea\13\2\2\2\u01e9\u01e8\3\2\2\2\u01ea"+
		"\u01ed\3\2\2\2\u01eb\u01ec\3\2\2\2\u01eb\u01e9\3\2\2\2\u01ec\u01ee\3\2"+
		"\2\2\u01ed\u01eb\3\2\2\2\u01ee\u01ef\7)\2\2\u01ef\u00a4\3\2\2\2\u01f0"+
		"\u01f4\7$\2\2\u01f1\u01f3\13\2\2\2\u01f2\u01f1\3\2\2\2\u01f3\u01f6\3\2"+
		"\2\2\u01f4\u01f5\3\2\2\2\u01f4\u01f2\3\2\2\2\u01f5\u01f7\3\2\2\2\u01f6"+
		"\u01f4\3\2\2\2\u01f7\u01f8\7$\2\2\u01f8\u00a6\3\2\2\2\u01f9\u01fd\t\3"+
		"\2\2\u01fa\u01fc\t\4\2\2\u01fb\u01fa\3\2\2\2\u01fc\u01ff\3\2\2\2\u01fd"+
		"\u01fb\3\2\2\2\u01fd\u01fe\3\2\2\2\u01fe\u00a8\3\2\2\2\u01ff\u01fd\3\2"+
		"\2\2\u0200\u0202\t\5\2\2\u0201\u0200\3\2\2\2\u0202\u0203\3\2\2\2\u0203"+
		"\u0201\3\2\2\2\u0203\u0204\3\2\2\2\u0204\u0205\3\2\2\2\u0205\u0206\bU"+
		"\2\2\u0206\u00aa\3\2\2\2\u0207\u0208\7\61\2\2\u0208\u0209\7,\2\2\u0209"+
		"\u020d\3\2\2\2\u020a\u020c\13\2\2\2\u020b\u020a\3\2\2\2\u020c\u020f\3"+
		"\2\2\2\u020d\u020e\3\2\2\2\u020d\u020b\3\2\2\2\u020e\u0210\3\2\2\2\u020f"+
		"\u020d\3\2\2\2\u0210\u0211\7,\2\2\u0211\u0212\7\61\2\2\u0212\u0213\3\2"+
		"\2\2\u0213\u0214\bV\3\2\u0214\u00ac\3\2\2\2\u0215\u0216\7\61\2\2\u0216"+
		"\u0217\7\61\2\2\u0217\u021b\3\2\2\2\u0218\u021a\n\6\2\2\u0219\u0218\3"+
		"\2\2\2\u021a\u021d\3\2\2\2\u021b\u0219\3\2\2\2\u021b\u021c\3\2\2\2\u021c"+
		"\u021e\3\2\2\2\u021d\u021b\3\2\2\2\u021e\u021f\bW\3\2\u021f\u00ae\3\2"+
		"\2\2\16\2\u01c0\u01d0\u01da\u01df\u01e5\u01eb\u01f4\u01fd\u0203\u020d"+
		"\u021b\4\b\2\2\2\3\2";
	public static final ATN _ATN =
		new ATNDeserializer().deserialize(_serializedATN.toCharArray());
	static {
		_decisionToDFA = new DFA[_ATN.getNumberOfDecisions()];
		for (int i = 0; i < _ATN.getNumberOfDecisions(); i++) {
			_decisionToDFA[i] = new DFA(_ATN.getDecisionState(i), i);
		}
	}
}