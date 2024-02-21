import mysql, { RowDataPacket } from "mysql2/promise";

type Client = mysql.Connection | mysql.Pool;

export const getAuthorQuery = `-- name: GetAuthor :one
SELECT id, name, bio FROM authors
WHERE id = ? LIMIT 1`;

export interface GetAuthorArgs {
    id: number;
}

export interface GetAuthorRow {
    id: number;
    name: string;
    bio: string | null;
}

export async function getAuthor(client: Client, args: GetAuthorArgs): Promise<GetAuthorRow | null> {
    const [rows] = await client.query<RowDataPacket[]>({
        sql: getAuthorQuery,
        values: [args.id],
        rowsAsArray: true
    });
    if (rows.length !== 1) {
        return null;
    }
    const row = rows[0];
    return {
        id: row[0],
        name: row[1],
        bio: row[2]
    };
}

export const listAuthorsQuery = `-- name: ListAuthors :many
SELECT id, name, bio FROM authors
ORDER BY name`;

export interface ListAuthorsRow {
    id: number;
    name: string;
    bio: string | null;
}

export async function listAuthors(client: Client): Promise<ListAuthorsRow[]> {
    const [rows] = await client.query<RowDataPacket[]>({
        sql: listAuthorsQuery,
        values: [],
        rowsAsArray: true
    });
    return rows.map(row => {
        return {
            id: row[0],
            name: row[1],
            bio: row[2]
        };
    });
}

export const createAuthorQuery = `-- name: CreateAuthor :exec
INSERT INTO authors (
  name, bio
) VALUES (
  ?, ? 
)`;

export interface CreateAuthorArgs {
    name: string;
    bio: string | null;
}

export async function createAuthor(client: Client, args: CreateAuthorArgs): Promise<void> {
    await client.query({
        sql: createAuthorQuery,
        values: [args.name, args.bio]
    });
}

export const deleteAuthorQuery = `-- name: DeleteAuthor :exec
DELETE FROM authors
WHERE id = ?`;

export interface DeleteAuthorArgs {
    id: number;
}

export async function deleteAuthor(client: Client, args: DeleteAuthorArgs): Promise<void> {
    await client.query({
        sql: deleteAuthorQuery,
        values: [args.id]
    });
}

export const testQuery = `-- name: Test :one
SELECT c_bit, c_tinyint, c_bool, c_boolean, c_smallint, c_mediumint, c_int, c_integer, c_bigint, c_serial, c_decimal, c_dec, c_numeric, c_fixed, c_float, c_double, c_double_precision, c_date, c_time, c_datetime, c_timestamp, c_year, c_char, c_nchar, c_national_char, c_varchar, c_binary, c_varbinary, c_tinyblob, c_tinytext, c_blob, c_text, c_mediumblob, c_mediumtext, c_longblob, c_longtext, c_json FROM node_mysql_types
LIMIT 1`;

export interface TestRow {
    cBit: Buffer | null;
    cTinyint: number | null;
    cBool: number | null;
    cBoolean: number | null;
    cSmallint: number | null;
    cMediumint: number | null;
    cInt: number | null;
    cInteger: number | null;
    cBigint: number | null;
    cSerial: number;
    cDecimal: string | null;
    cDec: string | null;
    cNumeric: string | null;
    cFixed: string | null;
    cFloat: number | null;
    cDouble: number | null;
    cDoublePrecision: number | null;
    cDate: Date | null;
    cTime: string | null;
    cDatetime: Date | null;
    cTimestamp: Date | null;
    cYear: number | null;
    cChar: string | null;
    cNchar: string | null;
    cNationalChar: string | null;
    cVarchar: string | null;
    cBinary: Buffer | null;
    cVarbinary: Buffer | null;
    cTinyblob: Buffer | null;
    cTinytext: string | null;
    cBlob: Buffer | null;
    cText: string | null;
    cMediumblob: Buffer | null;
    cMediumtext: string | null;
    cLongblob: Buffer | null;
    cLongtext: string | null;
    cJson: any | null;
}

export async function test(client: Client): Promise<TestRow | null> {
    const [rows] = await client.query<RowDataPacket[]>({
        sql: testQuery,
        values: [],
        rowsAsArray: true
    });
    if (rows.length !== 1) {
        return null;
    }
    const row = rows[0];
    return {
        cBit: row[0],
        cTinyint: row[1],
        cBool: row[2],
        cBoolean: row[3],
        cSmallint: row[4],
        cMediumint: row[5],
        cInt: row[6],
        cInteger: row[7],
        cBigint: row[8],
        cSerial: row[9],
        cDecimal: row[10],
        cDec: row[11],
        cNumeric: row[12],
        cFixed: row[13],
        cFloat: row[14],
        cDouble: row[15],
        cDoublePrecision: row[16],
        cDate: row[17],
        cTime: row[18],
        cDatetime: row[19],
        cTimestamp: row[20],
        cYear: row[21],
        cChar: row[22],
        cNchar: row[23],
        cNationalChar: row[24],
        cVarchar: row[25],
        cBinary: row[26],
        cVarbinary: row[27],
        cTinyblob: row[28],
        cTinytext: row[29],
        cBlob: row[30],
        cText: row[31],
        cMediumblob: row[32],
        cMediumtext: row[33],
        cLongblob: row[34],
        cLongtext: row[35],
        cJson: row[36]
    };
}
